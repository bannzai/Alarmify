import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { generateApiToken, parseBearerToken } from "../lib/apiToken.js";
import type { Deps } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { planLimits } from "../lib/plan.js";
import { ensureUser, userRef } from "../lib/store.js";
import {
  alarmHistoryLimitSchema,
  collections,
  createApiTokenRequestSchema,
  registerDeviceRequestSchema,
} from "../schema/index.js";

function currentUid(res: Response): string {
  const uid = res.locals.uid;
  if (typeof uid !== "string") {
    throw new ApiError(401, "unauthenticated", "認証情報がありません");
  }
  return uid;
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
 * アプリ向け API。Firebase Auth の ID トークンで認証する。
 * App Check による保護は #4 で追加する
 */
export function createAppApi(deps: Deps): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));
  app.use(authenticate(deps));

  // 端末の FCM トークンを登録する。同じ device_id への再登録で上書きする (冪等)
  app.post("/v1/devices", async (req, res) => {
    const parsed = registerDeviceRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const uid = currentUid(res);
    const now = deps.now();
    await ensureUser(deps.firestore, uid, now);

    const ref = userRef(deps.firestore, uid)
      .collection(collections.devices)
      .doc(parsed.data.device_id);
    await deps.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const createdAt = snapshot.exists ? snapshot.get("createdAt") : Timestamp.fromDate(now);
      transaction.set(ref, {
        fcmToken: parsed.data.fcm_token,
        platform: parsed.data.platform,
        createdAt,
        updatedAt: Timestamp.fromDate(now),
      });
    });
    res.status(200).json({ device_id: parsed.data.device_id, platform: parsed.data.platform });
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
    const user = await ensureUser(deps.firestore, uid, now);
    const tokensRef = userRef(deps.firestore, uid).collection(collections.apiTokens);

    const limit = planLimits[user.plan].apiTokens;
    if (Number.isFinite(limit)) {
      const active = await tokensRef.where("revokedAt", "==", null).limit(limit).get();
      if (active.size >= limit) {
        throw new ApiError(
          403,
          "plan_limit_exceeded",
          `${user.plan} プランで発行できる API トークンは ${limit} 個までです`,
        );
      }
    }

    const generated = generateApiToken();
    const ref = tokensRef.doc();
    await ref.set({
      name: parsed.data.name,
      hash: generated.hash,
      prefix: generated.prefix,
      createdAt: Timestamp.fromDate(now),
      lastUsedAt: null,
      revokedAt: null,
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

  app.get("/v1/api-tokens", async (_req, res) => {
    const uid = currentUid(res);
    const snapshot = await userRef(deps.firestore, uid)
      .collection(collections.apiTokens)
      .where("revokedAt", "==", null)
      .limit(100)
      .get();
    res.status(200).json({
      api_tokens: snapshot.docs.map((doc) => ({
        id: doc.id,
        name: doc.get("name"),
        prefix: doc.get("prefix"),
        created_at: (doc.get("createdAt") as Timestamp | undefined)?.toDate().toISOString() ?? null,
        last_used_at: (doc.get("lastUsedAt") as Timestamp | null | undefined)?.toDate().toISOString() ?? null,
      })),
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
    const parsedLimit = alarmHistoryLimitSchema.safeParse(req.query.limit ?? undefined);
    if (!parsedLimit.success) {
      throw badRequestFromZod(parsedLimit.error);
    }
    const uid = currentUid(res);
    const snapshot = await userRef(deps.firestore, uid)
      .collection(collections.alarms)
      .orderBy("createdAt", "desc")
      .limit(parsedLimit.data)
      .get();
    res.status(200).json({
      alarms: snapshot.docs.map((doc) => ({
        id: doc.id,
        status: doc.get("status"),
        title: doc.get("title"),
        fire_at: (doc.get("fireAt") as Timestamp).toDate().toISOString(),
        created_at: (doc.get("createdAt") as Timestamp).toDate().toISOString(),
        token_id: doc.get("tokenId"),
      })),
    });
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
