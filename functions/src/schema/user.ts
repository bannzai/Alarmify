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

/** users/{uid} */
export const userSchema = z.object({
  plan: planSchema,
  monthlyUsage: monthlyUsageSchema,
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
});
export type User = z.infer<typeof userSchema>;
