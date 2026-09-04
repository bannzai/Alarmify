import { timingSafeEqual } from "node:crypto";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import type { Deps } from "../lib/deps.js";
import { ApiError, badRequestFromZod, errorHandler, notFoundHandler } from "../lib/errors.js";
import { planUpdatesOf, revenueCatWebhookBodySchema, type PlanUpdate } from "../lib/revenueCat.js";
import { deletionMarkerRef, newUserDocument, userRef } from "../lib/store.js";

export interface RevenueCatWebhookOptions {
  /**
   * RevenueCat Dashboard の webhook 設定に登録した Authorization ヘッダーの値。
   * 値は Secret Manager から起動時に読むため関数で受け取る。空文字は「未設定」として全リクエストを拒否する
   */
  authorization: () => string;
}

/** ヘッダーの値と設定値の比較。長さの違いを含めてタイミング差を残さない */
function authorizationMatches(header: string | undefined, expected: string): boolean {
  if (!header || !expected) {
    return false;
  }
  const left = Buffer.from(header, "utf8");
  const right = Buffer.from(expected, "utf8");
  if (left.length !== right.length) {
    return false;
  }
  return timingSafeEqual(left, right);
}

function authenticate(options: RevenueCatWebhookOptions) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!authorizationMatches(req.header("authorization"), options.authorization())) {
      next(new ApiError(401, "unauthenticated", "Authorization ヘッダーが一致しません"));
      return;
    }
    next();
  };
}

/** 1 件の更新の結果。ログと応答に載せる (uid は載せない) */
export type PlanUpdateOutcome = "applied" | "stale" | "unknown_user" | "account_deleted";

/**
 * プランを users/{uid} に書く。
 * - 保存済みの planEventAt より古いイベントは書かない (再送・順序の入れ替わりで新しい状態を巻き戻さない)
 * - ユーザーのドキュメントが無い時は、pro にする更新に限って作る (購入を取りこぼさない)。free にする更新は何も変えない
 * - 削除処理中 (目印がある) のアカウントには書かない (掃除の後にドキュメントを復活させない)
 * 同じイベントを何度受けても同じ状態に収束する (冪等)
 */
async function applyPlanUpdate(
  deps: Deps,
  update: PlanUpdate,
  eventAt: Date,
): Promise<PlanUpdateOutcome> {
  const now = deps.now();
  const userDocRef = userRef(deps.firestore, update.uid);
  return deps.firestore.runTransaction(async (transaction) => {
    const marker = await transaction.get(deletionMarkerRef(deps.firestore, update.uid));
    if (marker.exists) {
      return "account_deleted";
    }
    const snapshot = await transaction.get(userDocRef);
    const storedEventAt = snapshot.exists ? (snapshot.get("planEventAt") as Timestamp | undefined) : undefined;
    if (storedEventAt && storedEventAt.toMillis() > eventAt.getTime()) {
      return "stale";
    }
    const fields = {
      plan: update.plan,
      proExpiresAt: update.proExpiresAt ? Timestamp.fromDate(update.proExpiresAt) : null,
      planEventAt: Timestamp.fromDate(eventAt),
      updatedAt: Timestamp.fromDate(now),
    };
    if (snapshot.exists) {
      transaction.update(userDocRef, fields);
      return "applied";
    }
    if (update.plan !== "pro") {
      return "unknown_user";
    }
    transaction.set(userDocRef, { ...newUserDocument(now), ...fields });
    return "applied";
  });
}

/**
 * RevenueCat の webhook (https://www.revenuecat.com/docs/integrations/webhooks) を受けて users/{uid}.plan を更新する。
 * 端末が起動していなくても購読の更新・失効に追従できるよう、アプリからの申告ではなく RevenueCat からの通知を正にする
 * (方式の選定は documents/adr/0005-sync-plan-with-revenuecat-webhook.md)。
 * 認証は Dashboard に登録した Authorization ヘッダーの一致のみ。App Check の対象外
 */
export function createRevenueCatWebhook(deps: Deps, options: RevenueCatWebhookOptions): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "64kb" }));
  app.use(authenticate(options));

  // RevenueCat は 2xx 以外を最大 5 回再送する。処理できない形式は 400 で返し、対象外のイベントは 200 で受け取ったことにする
  app.post("/", async (req, res) => {
    const parsed = revenueCatWebhookBodySchema.safeParse(req.body);
    if (!parsed.success) {
      throw badRequestFromZod(parsed.error);
    }
    const event = parsed.data.event;
    const eventAt = new Date(event.event_timestamp_ms);
    const updates = planUpdatesOf(event, deps.now());
    const outcomes: PlanUpdateOutcome[] = [];
    for (const update of updates) {
      outcomes.push(await applyPlanUpdate(deps, update, eventAt));
    }
    // uid は識別子のためログに残さない
    logger.info("revenuecat webhook", { type: event.type, eventId: event.id, outcomes });
    res.status(200).json({ event_id: event.id, outcomes });
  });

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
