import { z } from "zod";
import { timestampSchema } from "./firestore.js";

/**
 * budgetNotifications/{budgetId}。
 * Cloud Billing の予算通知 (Pub/Sub) を Slack へ転送した記録。
 * 予算通知は閾値の超過に関係なく 1 日に複数回届き、超過後はどのメッセージにも同じ閾値が載るため、
 * 集計期間ごとに「どの閾値まで Slack に流したか」を覚えて同じ閾値を二度投稿しない
 */
export const budgetNotificationSchema = z.object({
  /** 通知が指す集計期間の開始 (予算通知の `costIntervalStart` をそのまま保存する)。期間が変われば閾値の記録を捨てる */
  costIntervalStart: z.string().min(1),
  /** その期間に Slack へ投稿した閾値のうち最大のもの (0.5 = 50%) */
  notifiedThresholdPercent: z.number().nonnegative(),
  updatedAt: timestampSchema,
});
export type BudgetNotification = z.infer<typeof budgetNotificationSchema>;

/** budgetNotifications/{budgetId} のフィールド名。書き込み・クエリ・テストはこの定数を通す */
export const budgetNotificationFields = {
  costIntervalStart: "costIntervalStart",
  notifiedThresholdPercent: "notifiedThresholdPercent",
  updatedAt: "updatedAt",
} as const satisfies Record<keyof BudgetNotification, string>;
