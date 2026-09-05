import type { Timestamp } from "firebase-admin/firestore";
import type { Plan } from "../schema/index.js";

export interface PlanLimits {
  /** 同時に持てる有効な API トークンの数 */
  apiTokens: number;
  /** 1 か月 (UTC) に登録できるアラームの数 */
  alarmsPerMonth: number;
}

/** プランごとの上限。plan の更新は RevenueCat の webhook (api/revenueCatWebhook.ts) が行う */
export const planLimits: Record<Plan, PlanLimits> = {
  free: { apiTokens: 1, alarmsPerMonth: 20 },
  pro: { apiTokens: Number.POSITIVE_INFINITY, alarmsPerMonth: Number.POSITIVE_INFINITY },
};

/** 月間上限の集計キー (UTC の YYYY-MM) */
export function monthKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = `${date.getUTCMonth() + 1}`.padStart(2, "0");
  return `${year}-${month}`;
}

/**
 * 今この瞬間に適用するプラン。
 * users/{uid}.plan は webhook が最後に観測した状態で、失効の webhook が遅れる・失われることがあるため、
 * pro は失効日時 (proExpiresAt) を過ぎていない間だけ有効として扱う。失効日時ちょうどは失効済み。
 * 失効日時が無い (null / 未設定) pro は期限なしとして plan の値をそのまま使う。純粋関数であり冪等
 */
export function effectivePlan(
  user: { plan: Plan; proExpiresAt?: Timestamp | null },
  now: Date,
): Plan {
  if (user.plan !== "pro") {
    return "free";
  }
  if (user.proExpiresAt === null || user.proExpiresAt === undefined) {
    return "pro";
  }
  return user.proExpiresAt.toMillis() > now.getTime() ? "pro" : "free";
}
