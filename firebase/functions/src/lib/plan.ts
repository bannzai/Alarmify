import type { Timestamp } from "firebase-admin/firestore";
import type { Plan } from "../schema/index.js";

export interface PlanLimits {
  /** 同時に持てる有効な API トークンの数 */
  apiTokens: number;
  /** 1 か月 (UTC) に登録できるアラームの数 */
  alarmsPerMonth: number;
  /** GET /v1/alarms で返す履歴の件数の上限 */
  alarmHistory: number;
  /** 1 回のアラームを配送する端末の数。登録済みの端末を登録順に数えて、この数までへ送る */
  deliveryDevices: number;
}

/** プランごとの上限。plan の更新は RevenueCat の webhook (api/revenueCatWebhook.ts) が行う */
export const planLimits: Record<Plan, PlanLimits> = {
  // alarmHistory の 3 件は「直近の Webhook が届いたか」を確かめられる最小の件数。
  // 履歴は Pro の機能 (documents/PROJECT.md「コア体験」4) のため、無料では機能の存在が分かる程度に留める
  // 月間上限は Issue #90 の商品設計。Pro を月 1000 件・3 台で使い切る原価の試算は約 $0.10。
  // 複数端末への配送は同じ商品設計で Pro の特典としたため、無料は受信端末 1 台に絞る。
  // Pro の上限は登録できる端末数 (MAX_DEVICES_PER_USER) で頭打ちになるため、プラン側では設けない。
  // https://github.com/bannzai/Alarmify/issues/90#issuecomment-5651147821
  free: { apiTokens: 1, alarmsPerMonth: 50, alarmHistory: 3, deliveryDevices: 1 },
  pro: {
    apiTokens: Number.POSITIVE_INFINITY,
    alarmsPerMonth: 1000,
    alarmHistory: Number.POSITIVE_INFINITY,
    deliveryDevices: Number.POSITIVE_INFINITY,
  },
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
