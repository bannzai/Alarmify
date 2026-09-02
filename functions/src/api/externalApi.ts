import { randomUUID } from "node:crypto";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { isApiTokenFormat, parseBearerToken } from "../lib/apiToken.js";
import type { Deps } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { monthKey, planLimits } from "../lib/plan.js";
import { buildAlarmMessage, type PushResult } from "../lib/push.js";
import { createRateLimiter } from "../lib/rateLimit.js";
import { expiresAtOf, findUserByApiToken, listDevices, userRef } from "../lib/store.js";
import {
  collections,
  createAlarmRequestSchema,
  userSchema,
  type Alarm,
  type AlarmStatus,
} from "../schema/index.js";

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

/** 1 クライアント (IP) あたりの上限。Function インスタンスごとの一次防御 */
export const EXTERNAL_RATE_LIMIT = { limit: 60, windowMs: 60_000 };

function rateLimit(deps: Deps) {
  const limiter = createRateLimiter({ ...EXTERNAL_RATE_LIMIT, now: deps.now });
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (limiter.consume(req.ip ?? "unknown")) {
      next();
      return;
    }
    next(new ApiError(429, "rate_limited", "リクエストが多すぎます。しばらく待って再試行してください"));
  };
}

function authenticate(deps: Deps) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const plainToken = parseBearerToken(req.header("authorization"));
    // 形式が違うトークンは Firestore を引かずに弾く (認証前の読み取りを増やさない)
    if (!plainToken || !isApiTokenFormat(plainToken)) {
      next(new ApiError(401, "unauthenticated", "Authorization: Bearer <API トークン> が必要です"));
      return;
    }
    const resolved = await findUserByApiToken(deps.firestore, plainToken);
    if (!resolved) {
      next(new ApiError(401, "unauthenticated", "API トークンが無効です"));
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

async function deliver(
  deps: Deps,
  uid: string,
  alarm: { id: string; action: "schedule" | "cancel"; fireAt: Date | null; title: string | null },
): Promise<PushResult> {
  const devices = await listDevices(deps.firestore, uid);
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
  return deps.sendPush(messages);
}

function alarmResponse(
  id: string,
  status: AlarmStatus,
  fireAt: Date,
  title: string | null,
  delivery: PushResult,
): Record<string, unknown> {
  return {
    id,
    status,
    fire_at: fireAt.toISOString(),
    title,
    delivery: { success_count: delivery.successCount, failure_count: delivery.failureCount },
  };
}

/** 外部サービス向け API。認証は Bearer の API トークンのみ (App Check の対象外。ADR 0001) */
export function createExternalApi(deps: Deps): Express {
  const app = express();
  app.disable("x-powered-by");
  // Cloud Run のロードバランサ配下で X-Forwarded-For から呼び出し元 IP を取る
  app.set("trust proxy", true);
  app.use(rateLimit(deps));
  app.use(express.json({ limit: "32kb" }));
  app.use(authenticate(deps));

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

    const alarmId = randomUUID();
    const title = parsed.data.title ?? null;
    const alarmRef = userRef(deps.firestore, uid).collection(collections.alarms).doc(alarmId);

    // 月間上限の判定とアラーム要求の作成を同じトランザクションで行い、上限を超えて登録されないようにする
    await deps.firestore.runTransaction(async (transaction) => {
      const userSnapshot = await transaction.get(userRef(deps.firestore, uid));
      if (!userSnapshot.exists) {
        throw new ApiError(404, "not_found", "ユーザーが見つかりません");
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
      transaction.update(userRef(deps.firestore, uid), {
        monthlyUsage: { month: currentMonth, scheduledAlarmCount: used + 1 },
        updatedAt: Timestamp.fromDate(now),
      });
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
    });

    const delivery = await deliver(deps, uid, {
      id: alarmId,
      action: "schedule",
      fireAt,
      title,
    });
    await alarmRef.update({
      delivery: {
        sentAt: Timestamp.fromDate(deps.now()),
        successCount: delivery.successCount,
        failureCount: delivery.failureCount,
        errors: delivery.errors,
      },
    });

    res.status(201).json(alarmResponse(alarmId, "scheduled", fireAt, title, delivery));
  });

  // 登録済みのアラームを取り消す。取り消し済みでも同じ応答を返す (冪等)
  app.delete("/v1/alarms/:alarmId", async (req, res) => {
    const { uid } = currentCaller(res);
    const alarmRef = userRef(deps.firestore, uid)
      .collection(collections.alarms)
      .doc(req.params.alarmId);
    const snapshot = await alarmRef.get();
    if (!snapshot.exists) {
      throw new ApiError(404, "not_found", "アラームが見つかりません");
    }
    const fireAt = (snapshot.get("fireAt") as Timestamp).toDate();
    const title = (snapshot.get("title") as string | null) ?? null;

    if (snapshot.get("status") !== "canceled") {
      await alarmRef.update({ status: "canceled", updatedAt: Timestamp.fromDate(deps.now()) });
    }
    const delivery = await deliver(deps, uid, {
      id: req.params.alarmId,
      action: "cancel",
      fireAt: null,
      title,
    });
    res.status(200).json(alarmResponse(req.params.alarmId, "canceled", fireAt, title, delivery));
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
