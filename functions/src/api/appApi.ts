import express, { type Express, type NextFunction, type Request, type Response } from "express";
import {
  FieldPath,
  Timestamp,
  type DocumentData,
  type Query,
  type QuerySnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import { generateApiToken, parseBearerToken } from "../lib/apiToken.js";
import { requireAppCheck } from "../lib/appCheck.js";
import type { Deps } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { planLimits } from "../lib/plan.js";
import { decodeCursor, encodeCursor, type ListCursor } from "../lib/cursor.js";
import { deletionMarkerRef, MAX_DEVICES_PER_USER, newUserDocument, userRef } from "../lib/store.js";
import {
  alarmHistoryLimitSchema,
  collections,
  listCursorSchema,
  createApiTokenRequestSchema,
  registerDeviceRequestSchema,
  userSchema,
} from "../schema/index.js";

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

function authenticate(deps: Deps) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const idToken = parseBearerToken(req.header("authorization"));
    if (!idToken) {
      next(new ApiError(401, "unauthenticated", "Authorization: Bearer <Firebase ID トークン> が必要です"));
      return;
    }
    let uid: string;
    try {
      uid = (await deps.verifyIdToken(idToken)).uid;
    } catch {
      next(new ApiError(401, "unauthenticated", "ID トークンを検証できませんでした"));
      return;
    }
    res.locals.uid = uid;
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
      // 配送は登録済みの全端末に行う。取りこぼしが出ないよう、配送で見る上限と同じ数で登録を止める
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
      const plan = user?.plan ?? "free";
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
    const snapshot = await paginate(
      userRef(deps.firestore, uid).collection(collections.alarms),
      page,
    );
    res.status(200).json({
      alarms: snapshot.docs.map((doc) => ({
        id: doc.id,
        status: doc.get("status"),
        title: doc.get("title"),
        fire_at: (doc.get("fireAt") as Timestamp).toDate().toISOString(),
        created_at: (doc.get("createdAt") as Timestamp).toDate().toISOString(),
        token_id: doc.get("tokenId"),
      })),
      next_cursor: nextCursor(snapshot, page.limit),
    });
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
