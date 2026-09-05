import { z } from "zod";
import { timestampSchema } from "./firestore.js";

export const planSchema = z.enum(["free", "pro"]);
export type Plan = z.infer<typeof planSchema>;

/** 無料プランの月間上限を判定するためのカウンタ。month が変わった時点で 0 から数え直す */
export const monthlyUsageSchema = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/),
  scheduledAlarmCount: z.number().int().nonnegative(),
});
export type MonthlyUsage = z.infer<typeof monthlyUsageSchema>;

/**
 * users/{uid}。
 * plan は RevenueCat の webhook (revenueCatWebhook) が entitlement `pro` の状態から書く。
 * proExpiresAt / planEventAt は webhook の導入 (#19) で追加したため、それ以前のドキュメントには無い (Optional で読む)
 */
export const userSchema = z.object({
  plan: planSchema,
  /**
   * plan が pro の間の失効日時。null は期限なし (買い切り等)。
   * 失効の webhook が届かなくても pro のまま残らないよう、上限の判定は effectivePlan (lib/plan.ts) でこの値と現在時刻を突き合わせる
   */
  proExpiresAt: timestampSchema.nullable().optional(),
  /**
   * plan を反映した webhook イベントの発生時刻 (event_timestamp_ms)。
   * RevenueCat は再送・順序の入れ替わりがあり得るため、これより古いイベントで新しい状態を巻き戻さない
   */
  planEventAt: timestampSchema.optional(),
  monthlyUsage: monthlyUsageSchema,
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
});
export type User = z.infer<typeof userSchema>;
