import { randomUUID } from "node:crypto";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { hashApiToken, isApiTokenFormat, parseBearerToken } from "../lib/apiToken.js";
import type { Deps } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { monthKey, planLimits } from "../lib/plan.js";
import { alarmActionOf, buildAlarmMessage, type PushResult } from "../lib/push.js";
import { createRateLimiter, createRecentKeys, type RateLimit } from "../lib/rateLimit.js";
import {
  expiresAfter,
  expiresAtOf,
  findUserByApiToken,
  listDevices,
  userRef,
  type RegisteredDevice,
} from "../lib/store.js";
import {
  collections,
  createAlarmRequestSchema,
  userSchema,
  type Alarm,
  type AlarmStatus,
} from "../schema/index.js";

/**
 * 認証前に通る分の上限 (Function インスタンスあたり)。
 * 呼び出し元 IP は X-Forwarded-For を詐称できるため、認証前はキーを持たせずインスタンス単位で数える
 */
export const EXTERNAL_GLOBAL_RATE_LIMIT: RateLimit = { limit: 600, windowMs: 60_000 };
/** 認証後の上限。詐称できない API トークン単位で数え、正規の呼び出し元同士が影響し合わないようにする */
export const EXTERNAL_TOKEN_RATE_LIMIT: RateLimit = { limit: 60, windowMs: 60_000 };

export interface ExternalApiOptions {
  globalRateLimit?: RateLimit;
  tokenRateLimit?: RateLimit;
}

interface ExternalCaller {
  uid: string;
  tokenId: string;
}

function currentCaller(res: Response): ExternalCaller {
  const caller = res.locals.caller as ExternalCaller | undefined;
  if (!caller) {
    throw new ApiError(401, "unauthenticated", "認証情報がありません");
  }
  return caller;
}

function tooManyRequests(): ApiError {
  return new ApiError(429, "rate_limited", "リクエストが多すぎます。しばらく待って再試行してください");
}

/**
 * 実在が確認できたトークンを覚えておく時間と件数。
 * 認証そのものは毎回 Firestore で行うため、失効は即座に効く。ここで覚えるのはレート制限の枠の振り分けだけ
 */
const KNOWN_TOKEN_TTL_MS = 10 * 60 * 1000;
const KNOWN_TOKEN_MAX_KEYS = 1_000;

function authenticate(deps: Deps, options: Required<ExternalApiOptions>) {
  const unknownTokenLimiter = createRateLimiter({ ...options.globalRateLimit, now: deps.now });
  const tokenLimiter = createRateLimiter({ ...options.tokenRateLimit, now: deps.now });
  const knownTokens = createRecentKeys({
    now: deps.now,
    ttlMs: KNOWN_TOKEN_TTL_MS,
    maxKeys: KNOWN_TOKEN_MAX_KEYS,
  });

  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const plainToken = parseBearerToken(req.header("authorization"));
    // 形式が違うトークンは Firestore を引かずに弾く (認証前の読み取りを増やさない)
    if (!plainToken || !isApiTokenFormat(plainToken)) {
      next(new ApiError(401, "unauthenticated", "Authorization: Bearer <API トークン> が必要です"));
      return;
    }
    // 実在が未確認のトークンだけを共有の枠で数える。既知のトークンの呼び出しが、
    // でたらめなトークンの大量送信で 429 になるのを避ける
    const tokenHash = hashApiToken(plainToken);
    if (!knownTokens.has(tokenHash) && !unknownTokenLimiter.consume("unknown")) {
      next(tooManyRequests());
      return;
    }
    const resolved = await findUserByApiToken(deps.firestore, plainToken);
    if (!resolved) {
      next(new ApiError(401, "unauthenticated", "API トークンが無効です"));
      return;
    }
    knownTokens.add(tokenHash);
    if (!tokenLimiter.consume(`${resolved.uid}/${resolved.tokenId}`)) {
      next(tooManyRequests());
      return;
    }
    res.locals.caller = resolved;
    await userRef(deps.firestore, resolved.uid)
      .collection(collections.apiTokens)
      .doc(resolved.tokenId)
      .update({ lastUsedAt: Timestamp.fromDate(deps.now()) });
    next();
  };
}

/**
 * 登録済みの端末へ push を送る。
 * 配送の失敗で登録そのものを失敗させると、呼び出し側が id を受け取れないまま再試行して二重登録になるため、
 * 例外は結果として持ち帰る
 */
async function deliver(
  deps: Deps,
  devices: RegisteredDevice[],
  alarm: { id: string; action: "schedule" | "cancel"; fireAt: Date | null; title: string | null },
): Promise<PushResult> {
  const mode = deps.pushDeliveryMode();
  const messages = devices.map((device) =>
    buildAlarmMessage({
      fcmToken: device.fcmToken,
      id: alarm.id,
      action: alarm.action,
      fireAt: alarm.fireAt,
      title: alarm.title,
      mode,
    }),
  );
  try {
    return await deps.sendPush(messages);
  } catch (error) {
    console.error("push delivery failed", error);
    return {
      successCount: 0,
      failureCount: devices.length,
      errors: [error instanceof Error ? error.message : "unknown"],
    };
  }
}

interface AlarmState {
  status: AlarmStatus;
  fireAt: Date;
  title: string | null;
}

/**
 * 配送直前の状態を読み直す。
 * 登録と配送の間に取り消しが確定していた場合に、取り消し済みのアラームへ schedule の push を送らないようにする
 */
async function currentAlarmState(
  deps: Deps,
  uid: string,
  alarmId: string,
  fallback: AlarmState,
): Promise<AlarmState> {
  const snapshot = await userRef(deps.firestore, uid)
    .collection(collections.alarms)
    .doc(alarmId)
    .get();
  if (!snapshot.exists) {
    return fallback;
  }
  return {
    status: (snapshot.get("status") as AlarmStatus | undefined) ?? fallback.status,
    fireAt: (snapshot.get("fireAt") as Timestamp).toDate(),
    title: (snapshot.get("title") as string | null) ?? null,
  };
}

function alarmResponse(id: string, state: AlarmState, delivery: PushResult): Record<string, unknown> {
  return {
    id,
    status: state.status,
    fire_at: state.fireAt.toISOString(),
    title: state.title,
    delivery: { success_count: delivery.successCount, failure_count: delivery.failureCount },
  };
}

async function recordDelivery(
  deps: Deps,
  uid: string,
  alarmId: string,
  delivery: PushResult,
): Promise<void> {
  await userRef(deps.firestore, uid)
    .collection(collections.alarms)
    .doc(alarmId)
    .update({
      delivery: {
        sentAt: Timestamp.fromDate(deps.now()),
        successCount: delivery.successCount,
        failureCount: delivery.failureCount,
        errors: delivery.errors,
      },
    });
}

/** 外部サービス向け API。認証は Bearer の API トークンのみ (App Check の対象外。ADR 0001) */
export function createExternalApi(deps: Deps, options: ExternalApiOptions = {}): Express {
  const resolvedOptions: Required<ExternalApiOptions> = {
    globalRateLimit: options.globalRateLimit ?? EXTERNAL_GLOBAL_RATE_LIMIT,
    tokenRateLimit: options.tokenRateLimit ?? EXTERNAL_TOKEN_RATE_LIMIT,
  };

  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));
  app.use(authenticate(deps, resolvedOptions));

  // 同じ id への POST は登録済みアラームの再スケジュールとして扱う (取り消し済みなら登録し直す)
  app.post("/v1/alarms", async (req, res) => {
    const parsed = createAlarmRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const { uid, tokenId } = currentCaller(res);
    const now = deps.now();
    const fireAt = parsed.data.fire_at;
    if (fireAt.getTime() <= now.getTime()) {
      throw new ApiError(400, "invalid_argument", "fire_at には未来の日時を指定してください");
    }

    const devices = await listDevices(deps.firestore, uid);
    if (devices.length === 0) {
      throw new ApiError(409, "no_device_registered", "アラームを配送する端末が登録されていません");
    }

    const alarmId = parsed.data.id ?? randomUUID();
    const title = parsed.data.title ?? null;
    const userDocRef = userRef(deps.firestore, uid);
    const alarmRef = userDocRef.collection(collections.alarms).doc(alarmId);

    // 月間上限の判定と書き込みを同じトランザクションで行う。
    // 上限を消費しないのは「同じ内容の再送」だけで、内容が変わる再スケジュールと取り消しからの再登録は消費する
    const created = await deps.firestore.runTransaction(async (transaction) => {
      const userSnapshot = await transaction.get(userDocRef);
      if (!userSnapshot.exists) {
        throw new ApiError(404, "not_found", "ユーザーが見つかりません");
      }
      const alarmSnapshot = await transaction.get(alarmRef);
      const isSameRequest =
        alarmSnapshot.exists &&
        alarmSnapshot.get("status") === "scheduled" &&
        (alarmSnapshot.get("fireAt") as Timestamp).toMillis() === fireAt.getTime() &&
        (((alarmSnapshot.get("title") as string | null) ?? null) === title);
      if (isSameRequest) {
        return false;
      }

      const user = userSchema.parse(userSnapshot.data());
      const currentMonth = monthKey(now);
      const used =
        user.monthlyUsage.month === currentMonth ? user.monthlyUsage.scheduledAlarmCount : 0;
      const limit = planLimits[user.plan].alarmsPerMonth;
      if (used >= limit) {
        throw new ApiError(
          403,
          "plan_limit_exceeded",
          `${user.plan} プランで登録できるアラームは月 ${limit} 件までです`,
        );
      }
      transaction.update(userDocRef, {
        monthlyUsage: { month: currentMonth, scheduledAlarmCount: used + 1 },
        updatedAt: Timestamp.fromDate(now),
      });

      if (alarmSnapshot.exists) {
        transaction.update(alarmRef, {
          title,
          fireAt: Timestamp.fromDate(fireAt),
          status: "scheduled",
          updatedAt: Timestamp.fromDate(now),
          expiresAt: expiresAtOf(now, fireAt),
        });
        return false;
      }
      const alarm: Alarm = {
        title,
        fireAt: Timestamp.fromDate(fireAt),
        status: "scheduled",
        tokenId,
        createdAt: Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
        expiresAt: expiresAtOf(now, fireAt),
        delivery: { sentAt: null, successCount: 0, failureCount: 0, errors: [] },
      };
      transaction.set(alarmRef, alarm);
      return true;
    });

    const state = await currentAlarmState(deps, uid, alarmId, {
      status: "scheduled",
      fireAt,
      title,
    });
    const delivery = await deliver(deps, devices, {
      id: alarmId,
      action: alarmActionOf(state.status),
      fireAt: state.status === "canceled" ? null : state.fireAt,
      title: state.title,
    });
    await recordDelivery(deps, uid, alarmId, delivery);

    res.status(created ? 201 : 200).json(alarmResponse(alarmId, state, delivery));
  });

  // 登録済みのアラームを取り消す。取り消し済みでも同じ応答を返す (冪等)
  app.delete("/v1/alarms/:alarmId", async (req, res) => {
    const { uid } = currentCaller(res);
    const alarmId = req.params.alarmId;
    const alarmRef = userRef(deps.firestore, uid).collection(collections.alarms).doc(alarmId);
    const snapshot = await alarmRef.get();
    if (!snapshot.exists) {
      throw new ApiError(404, "not_found", "アラームが見つかりません");
    }
    const now = deps.now();
    if (snapshot.get("status") !== "canceled") {
      await alarmRef.update({
        status: "canceled",
        updatedAt: Timestamp.fromDate(now),
        // 取り消したアラームを発火予定まで残す理由はないため、保持期間を取り消し時点から数え直す
        expiresAt: expiresAfter(now),
      });
    }

    const state = await currentAlarmState(deps, uid, alarmId, {
      status: "canceled",
      fireAt: (snapshot.get("fireAt") as Timestamp).toDate(),
      title: (snapshot.get("title") as string | null) ?? null,
    });
    const delivery = await deliver(deps, await listDevices(deps.firestore, uid), {
      id: alarmId,
      action: alarmActionOf(state.status),
      fireAt: state.status === "canceled" ? null : state.fireAt,
      title: state.title,
    });
    await recordDelivery(deps, uid, alarmId, delivery);

    res.status(200).json(alarmResponse(alarmId, state, delivery));
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
