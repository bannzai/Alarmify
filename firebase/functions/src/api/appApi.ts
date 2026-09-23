import express, { type Express, type NextFunction, type Request, type Response } from "express";
import {
  FieldPath,
  Timestamp,
  type DocumentData,
  type Query,
  type QueryDocumentSnapshot,
  type QuerySnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import { generateApiToken, parseBearerToken } from "../lib/apiToken.js";
import { requireAppCheck } from "../lib/appCheck.js";
import type { Deps, VerifiedIdToken } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { effectivePlan, planLimits } from "../lib/plan.js";
import { decodeCursor, encodeCursor, type ListCursor } from "../lib/cursor.js";
import {
  currentPlan,
  deletionMarkerRef,
  MAX_DEVICES_PER_USER,
  newUserDocument,
  userRef,
} from "../lib/store.js";
import {
  alarmHistoryLimitSchema,
  canonicalUuidSchema,
  collections,
  listCursorSchema,
  createApiTokenRequestSchema,
  mergeAnonymousAccountRequestSchema,
  registerDeviceRequestSchema,
  reportDeviceResultRequestSchema,
  userSchema,
  type DeviceReport,
} from "../schema/index.js";

/** 匿名認証で発行された ID トークンの `firebase.sign_in_provider` (Firebase Auth の仕様値) */
const ANONYMOUS_SIGN_IN_PROVIDER = "anonymous";

/**
 * 削除処理中 (目印がある) アカウントのデータを作り直さない。
 * 削除前に発行された ID トークンで届いた書き込みが、掃除の後にドキュメントを復活させないよう、書き込みと同じトランザクションで判定する
 */
async function rejectIfAccountDeleted(transaction: Transaction, deps: Deps, uid: string): Promise<void> {
  const marker = await transaction.get(deletionMarkerRef(deps.firestore, uid));
  if (marker.exists) {
    throw new ApiError(410, "account_deleted", "アカウントは削除されています");
  }
}

function currentUid(res: Response): string {
  const uid = res.locals.uid;
  if (typeof uid !== "string") {
    throw new ApiError(401, "unauthenticated", "認証情報がありません");
  }
  return uid;
}

interface Page {
  limit: number;
  cursor: ListCursor | null;
}

function parsePage(req: Request): Page {
  const parsedLimit = alarmHistoryLimitSchema.safeParse(req.query.limit ?? undefined);
  if (!parsedLimit.success) {
    throw badRequestFromZod(parsedLimit.error);
  }
  const parsedCursor = listCursorSchema.safeParse(req.query.cursor ?? undefined);
  if (!parsedCursor.success) {
    throw badRequestFromZod(parsedCursor.error);
  }
  if (!parsedCursor.data) {
    return { limit: parsedLimit.data, cursor: null };
  }
  const cursor = decodeCursor(parsedCursor.data);
  if (!cursor) {
    throw new ApiError(400, "invalid_argument", "cursor の形式が不正です");
  }
  return { limit: parsedLimit.data, cursor };
}

/**
 * 作成日時の新しい順に 1 ページ分を取る。
 * cursor には並び順の値を持たせ、そのドキュメントが削除されていても続きを辿れるようにする
 */
async function paginate(
  collection: Query<DocumentData>,
  page: Page,
): Promise<QuerySnapshot<DocumentData>> {
  const ordered = collection.orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc");
  const positioned = page.cursor
    ? ordered.startAfter(page.cursor.createdAt, page.cursor.id)
    : ordered;
  return positioned.limit(page.limit).get();
}

function nextCursor(snapshot: QuerySnapshot<DocumentData>, limit: number): string | null {
  if (snapshot.size < limit) {
    return null;
  }
  const last = snapshot.docs[snapshot.size - 1];
  return encodeCursor({ createdAt: last.get("createdAt") as Timestamp, id: last.id });
}

function alarmHistoryItem(doc: QueryDocumentSnapshot<DocumentData>): Record<string, unknown> {
  const delivery = doc.get("delivery") as { successCount: number; failureCount: number };
  const deviceReports = (doc.get("deviceReports") as Record<string, DeviceReport> | undefined) ?? {};
  return {
    id: doc.id,
    status: doc.get("status"),
    title: doc.get("title"),
    fire_at: (doc.get("fireAt") as Timestamp).toDate().toISOString(),
    created_at: (doc.get("createdAt") as Timestamp).toDate().toISOString(),
    updated_at: (doc.get("updatedAt") as Timestamp).toDate().toISOString(),
    token_id: doc.get("tokenId"),
    delivery: { success_count: delivery.successCount, failure_count: delivery.failureCount },
    // device_id の昇順に並べる (順序を安定させ、iOS 側の差分表示を予測可能にする)
    device_reports: Object.entries(deviceReports)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([deviceId, report]) => ({
        device_id: deviceId,
        action: report.action,
        result: report.result,
        error: report.error,
        occurred_at: (report.occurredAt as Timestamp).toDate().toISOString(),
      })),
  };
}

function authenticate(deps: Deps) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const idToken = parseBearerToken(req.header("authorization"));
    if (!idToken) {
      next(new ApiError(401, "unauthenticated", "Authorization: Bearer <Firebase ID トークン> が必要です"));
      return;
    }
    let verified: VerifiedIdToken;
    try {
      verified = await deps.verifyIdToken(idToken);
    } catch {
      next(new ApiError(401, "unauthenticated", "ID トークンを検証できませんでした"));
      return;
    }
    res.locals.uid = verified.uid;
    res.locals.signInProvider = verified.signInProvider;
    next();
  };
}

/**
 * アプリ向け API。Firebase Auth の ID トークンで認証し、App Check で正規のアプリからの呼び出しに限る。
 * App Check の検証を ID トークンの検証より先に置き、アプリ以外からの呼び出しは認証まで進ませない
 */
export function createAppApi(deps: Deps): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));
  app.use(requireAppCheck(deps));
  app.use(authenticate(deps));

  // 端末の FCM トークンを登録する。同じ device_id への再登録で上書きする (冪等)
  app.post("/v1/devices", async (req, res) => {
    const parsed = registerDeviceRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const uid = currentUid(res);
    const now = deps.now();
    const userDocRef = userRef(deps.firestore, uid);
    const devicesRef = userDocRef.collection(collections.devices);
    const deviceRef = devicesRef.doc(parsed.data.device_id);

    await deps.firestore.runTransaction(async (transaction) => {
      await rejectIfAccountDeleted(transaction, deps, uid);
      const userSnapshot = await transaction.get(userDocRef);
      const deviceSnapshot = await transaction.get(deviceRef);
      // 無料プランでも 2 台目以降の登録は受け付ける (アプリが起動時に自動登録するため、拒否すると 2 台目で使えなく見える)。
      // Pro の配送は登録済みの全端末に行うため、取りこぼしが出ないよう配送で見る上限と同じ数で登録を止める
      if (!deviceSnapshot.exists) {
        const registered = await transaction.get(devicesRef.limit(MAX_DEVICES_PER_USER));
        if (registered.size >= MAX_DEVICES_PER_USER) {
          throw new ApiError(
            403,
            "device_limit_exceeded",
            `登録できる端末は ${MAX_DEVICES_PER_USER} 台までです`,
          );
        }
      }
      if (!userSnapshot.exists) {
        transaction.set(userDocRef, newUserDocument(now));
      }
      transaction.set(deviceRef, {
        fcmToken: parsed.data.fcm_token,
        platform: parsed.data.platform,
        createdAt: deviceSnapshot.exists ? deviceSnapshot.get("createdAt") : Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
      });
    });
    res.status(200).json({ device_id: parsed.data.device_id, platform: parsed.data.platform });
  });

  // 上限に達した時に、使わなくなった端末を見つけて消せるようにする
  app.get("/v1/devices", async (_req, res) => {
    const uid = currentUid(res);
    const snapshot = await userRef(deps.firestore, uid)
      .collection(collections.devices)
      .orderBy("createdAt", "asc")
      .limit(MAX_DEVICES_PER_USER)
      .get();
    res.status(200).json({
      devices: snapshot.docs.map((doc) => ({
        device_id: doc.id,
        platform: doc.get("platform"),
        created_at: (doc.get("createdAt") as Timestamp).toDate().toISOString(),
        updated_at: (doc.get("updatedAt") as Timestamp).toDate().toISOString(),
      })),
    });
  });

  app.delete("/v1/devices/:deviceId", async (req, res) => {
    const uid = currentUid(res);
    await userRef(deps.firestore, uid)
      .collection(collections.devices)
      .doc(req.params.deviceId)
      .delete();
    res.status(204).send();
  });

  // 匿名ユーザーが既存の Apple アカウントでサインインした時に、匿名側の端末を呼び出し元 (Apple 側) へ移して匿名アカウントを消す。
  // Apple 側を正とし、API トークン・当月の利用数・プランは Apple 側のものを残す (無料枠をリセットしない)。
  // 統合元は ID トークンで本人であることを確かめ、匿名アカウントに限る (識別済みのアカウント同士を統合させない)。
  // 統合元が既に削除済みでも、移す端末が無いだけで同じ結果になる (冪等。応答が失われた後の再送を成功で終わらせる)
  app.post("/v1/account/merge", async (req, res) => {
    const parsed = mergeAnonymousAccountRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const uid = currentUid(res);
    if (res.locals.signInProvider === ANONYMOUS_SIGN_IN_PROVIDER) {
      throw new ApiError(403, "merge_target_anonymous", "統合先は匿名ではないアカウントに限ります");
    }
    let anonymous: VerifiedIdToken;
    try {
      anonymous = await deps.verifyIdToken(parsed.data.anonymous_id_token);
    } catch {
      throw new ApiError(400, "invalid_anonymous_id_token", "統合元の ID トークンを検証できませんでした");
    }
    if (anonymous.signInProvider !== ANONYMOUS_SIGN_IN_PROVIDER) {
      throw new ApiError(400, "invalid_anonymous_id_token", "統合元は匿名アカウントに限ります");
    }
    if (anonymous.uid === uid) {
      throw new ApiError(400, "invalid_anonymous_id_token", "統合元と統合先が同じアカウントです");
    }
    const now = deps.now();
    const userDocRef = userRef(deps.firestore, uid);
    const devicesRef = userDocRef.collection(collections.devices);
    const anonymousDevicesRef = userRef(deps.firestore, anonymous.uid).collection(collections.devices);

    const movedDevices = await deps.firestore.runTransaction(async (transaction) => {
      await rejectIfAccountDeleted(transaction, deps, uid);
      const userSnapshot = await transaction.get(userDocRef);
      const anonymousDevices = await transaction.get(
        anonymousDevicesRef.orderBy("createdAt", "asc").limit(MAX_DEVICES_PER_USER),
      );
      const registered = await transaction.get(devicesRef.limit(MAX_DEVICES_PER_USER));
      const registeredById = new Map(registered.docs.map((doc) => [doc.id, doc]));
      // 端末登録と同じ上限を超えて移さない。超えた分は移さずに匿名アカウントと一緒に消える
      // (匿名アカウントは端末ごとに作られるため、実際に移るのはサインインした端末の 1 台だけになる)
      let remaining = MAX_DEVICES_PER_USER - registered.size;
      let moved = 0;
      for (const device of anonymousDevices.docs) {
        const existing = registeredById.get(device.id);
        if (!existing) {
          if (remaining <= 0) {
            continue;
          }
          remaining -= 1;
        } else if (
          (existing.get("updatedAt") as Timestamp).toMillis() >= (device.get("updatedAt") as Timestamp).toMillis()
        ) {
          // 同じ端末が Apple 側で登録し直した値の方が新しい (FCM トークンのローテーション後) なら上書きしない
          continue;
        }
        transaction.set(devicesRef.doc(device.id), {
          fcmToken: device.get("fcmToken"),
          platform: device.get("platform"),
          // 無料プランの配送先は最初に登録した 1 台 (createdAt の昇順) のため、移した端末は今 Apple 側に登録した端末として扱い、
          // Apple 側で先に使っていた端末から配送先を奪わない
          createdAt: existing ? existing.get("createdAt") : Timestamp.fromDate(now),
          updatedAt: Timestamp.fromDate(now),
        });
        moved += 1;
      }
      if (!userSnapshot.exists && moved > 0) {
        transaction.set(userDocRef, newUserDocument(now));
      }
      return moved;
    });
    await deps.deleteUserAccount(anonymous.uid);
    res.status(200).json({ moved_devices: movedDevices });
  });

  // API トークンを発行する。平文はここでしか返さない
  app.post("/v1/api-tokens", async (req, res) => {
    const parsed = createApiTokenRequestSchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const uid = currentUid(res);
    const now = deps.now();
    const userDocRef = userRef(deps.firestore, uid);
    const tokensRef = userDocRef.collection(collections.apiTokens);
    const generated = generateApiToken();
    const ref = tokensRef.doc();

    // 上限の判定と発行を同じトランザクションで行い、同時実行で上限を超えて発行されないようにする
    await deps.firestore.runTransaction(async (transaction) => {
      await rejectIfAccountDeleted(transaction, deps, uid);
      const userSnapshot = await transaction.get(userDocRef);
      const user = userSnapshot.exists ? userSchema.parse(userSnapshot.data()) : null;
      // pro は失効日時を過ぎていない間だけ (失効の webhook が遅れても上限を解除したままにしない)
      const plan = user ? effectivePlan(user, now) : "free";
      const limit = planLimits[plan].apiTokens;
      if (Number.isFinite(limit)) {
        const active = await transaction.get(
          tokensRef.where("revokedAt", "==", null).limit(limit),
        );
        if (active.size >= limit) {
          throw new ApiError(
            403,
            "plan_limit_exceeded",
            `${plan} プランで発行できる API トークンは ${limit} 個までです`,
          );
        }
      }
      if (!user) {
        transaction.set(userDocRef, newUserDocument(now));
      }
      transaction.set(ref, {
        name: parsed.data.name,
        hash: generated.hash,
        prefix: generated.prefix,
        createdAt: Timestamp.fromDate(now),
        lastUsedAt: null,
        revokedAt: null,
      });
    });

    res.status(201).json({
      id: ref.id,
      name: parsed.data.name,
      prefix: generated.prefix,
      // 平文を返すのは発行時の 1 度だけ
      token: generated.token,
      created_at: now.toISOString(),
    });
  });

  app.get("/v1/api-tokens", async (req, res) => {
    const page = parsePage(req);
    const uid = currentUid(res);
    const snapshot = await paginate(
      userRef(deps.firestore, uid).collection(collections.apiTokens).where("revokedAt", "==", null),
      page,
    );
    res.status(200).json({
      api_tokens: snapshot.docs.map((doc) => ({
        id: doc.id,
        name: doc.get("name"),
        prefix: doc.get("prefix"),
        created_at: (doc.get("createdAt") as Timestamp).toDate().toISOString(),
        last_used_at: (doc.get("lastUsedAt") as Timestamp | null | undefined)?.toDate().toISOString() ?? null,
      })),
      next_cursor: nextCursor(snapshot, page.limit),
    });
  });

  // 失効させる。既に失効済みでも 204 を返す (冪等)
  app.delete("/v1/api-tokens/:tokenId", async (req, res) => {
    const uid = currentUid(res);
    const ref = userRef(deps.firestore, uid)
      .collection(collections.apiTokens)
      .doc(req.params.tokenId);
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      throw new ApiError(404, "not_found", "API トークンが見つかりません");
    }
    if (snapshot.get("revokedAt") === null) {
      await ref.update({ revokedAt: Timestamp.fromDate(deps.now()) });
    }
    res.status(204).send();
  });

  app.get("/v1/alarms", async (req, res) => {
    const page = parsePage(req);
    const uid = currentUid(res);
    const plan = await currentPlan(deps.firestore, uid, deps.now());
    const limit = Math.min(page.limit, planLimits[plan].alarmHistory);
    // free は直近 N 件だけを見せる機能のため、cursor を受け取っても先頭ページに固定し、次のページも案内しない
    const resolvedPage: Page = plan === "free" ? { limit, cursor: null } : { limit, cursor: page.cursor };
    const snapshot = await paginate(
      userRef(deps.firestore, uid).collection(collections.alarms),
      resolvedPage,
    );
    res.status(200).json({
      alarms: snapshot.docs.map((doc) => alarmHistoryItem(doc)),
      next_cursor: plan === "free" ? null : nextCursor(snapshot, limit),
    });
  });

  // 端末が push で届いた AlarmRequest を AlarmKit へ反映した結果を報告する。同じ device_id の再送は上書きになる (冪等)
  app.post("/v1/alarms/:alarmId/device-reports", async (req, res) => {
    const parsedId = canonicalUuidSchema.safeParse(req.params.alarmId);
    if (!parsedId.success) {
      throw badRequestFromZod(parsedId.error);
    }
    const parsedBody = reportDeviceResultRequestSchema.safeParse(req.body);
    if (!parsedBody.success) {
      throw badRequestFromZod(parsedBody.error);
    }
    const uid = currentUid(res);
    const alarmId = parsedId.data;
    const now = deps.now();
    const alarmRef = userRef(deps.firestore, uid).collection(collections.alarms).doc(alarmId);

    const deviceRef = userRef(deps.firestore, uid)
      .collection(collections.devices)
      .doc(parsedBody.data.device_id);

    await deps.firestore.runTransaction(async (transaction) => {
      await rejectIfAccountDeleted(transaction, deps, uid);
      const snapshot = await transaction.get(alarmRef);
      if (!snapshot.exists) {
        // 古いデプロイの appApi はこのエンドポイント自体が無く、notFoundHandler が code "not_found" の 404 を返す。
        // iOS 側はアラームが本当に無い 404 だけ報告を捨てられるよう、code で区別できるようにする
        throw new ApiError(404, "alarm_not_found", "アラームが見つかりません");
      }
      // 任意の device_id で報告を書けると 1 つのアラーム文書に無制限にキーが増える (端末登録の上限を迂回する)ため、
      // 登録済みの端末からの報告だけ受け付ける
      const deviceSnapshot = await transaction.get(deviceRef);
      if (!deviceSnapshot.exists) {
        throw new ApiError(404, "device_not_found", "端末が登録されていません");
      }
      if (parsedBody.data.action === "schedule" && parsedBody.data.fire_at !== undefined) {
        // push payload の fire_at は toIso8601Seconds で秒までに丸めて配送し、端末もその値をそのまま返す。
        // 一方 fire_in で登録したアラームの Firestore 上の fireAt はミリ秒を持つため、秒単位に揃えてから比べる
        const registeredFireAtSeconds = Math.floor(
          (snapshot.get("fireAt") as Timestamp).toMillis() / 1000,
        );
        const reportedFireAtSeconds = Math.floor(parsedBody.data.fire_at.getTime() / 1000);
        if (registeredFireAtSeconds !== reportedFireAtSeconds) {
          // 同じ id で再スケジュールされた後に遅れて届いた、前の登録に対する報告を弾く。
          // 再スケジュール時に空にした deviceReports を古い内容で埋め直さないよう、何も書き込まない
          throw new ApiError(
            409,
            "alarm_revision_mismatch",
            "報告の発火時刻が現在の登録と一致しません",
          );
        }
      }
      const deviceReports =
        (snapshot.get("deviceReports") as Record<string, DeviceReport> | undefined) ?? {};
      const existingReport = deviceReports[parsedBody.data.device_id];
      const occurredAt = Timestamp.fromDate(parsedBody.data.occurred_at);
      // 同じ登録に対する報告でも、再試行や並行送信で HTTP の到着順が入れ替わると後着が勝ってしまい、
      // 新しい失敗を古い成功で上書きし得るため、端末の時計 (occurredAt) で見て古い報告は捨てる。
      // occurredAt が同じ場合は上書きする (内容を変えて再送した場合の既存の挙動を維持する)
      if (existingReport && existingReport.occurredAt.toMillis() > occurredAt.toMillis()) {
        return;
      }
      const report: DeviceReport = {
        action: parsedBody.data.action,
        result: parsedBody.data.result,
        error: parsedBody.data.error ?? null,
        occurredAt,
        reportedAt: Timestamp.fromDate(now),
      };
      // device_id に "." が含まれても入れ子として解釈させないよう、文字列のドットパスではなく FieldPath のセグメントで書き込む
      transaction.update(alarmRef, new FieldPath("deviceReports", parsedBody.data.device_id), report);
    });

    res.status(200).json({ alarm_id: alarmId, device_id: parsedBody.data.device_id });
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
