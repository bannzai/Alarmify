import type { Plan } from "../schema/index.js";

export interface PlanLimits {
  /** 同時に持てる有効な API トークンの数 */
  apiTokens: number;
  /** 1 か月 (UTC) に登録できるアラームの数 */
  alarmsPerMonth: number;
}

/** 課金の entitlement 連携は #7 で行う。ここではサーバー側の判定だけを持つ */
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
