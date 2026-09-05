import { z } from "zod";
import type { Plan } from "../schema/index.js";

/** iOS 側 (ProEntitlement.entitlementIdentifier) と RevenueCat の entitlement の lookup_key に揃える */
export const PRO_ENTITLEMENT_ID = "pro";

/**
 * RevenueCat の webhook が送るイベントのうち、プランの判定に使う部分だけ。
 * 使わないフィールドは読み飛ばす (RevenueCat 側のフィールド追加で壊れないようにする)。
 * 形式: https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
 */
export const revenueCatEventSchema = z.object({
  id: z.string().min(1),
  type: z.string().min(1),
  event_timestamp_ms: z.number().int().nonnegative(),
  app_user_id: z.string().optional(),
  aliases: z.array(z.string()).nullable().optional(),
  entitlement_ids: z.array(z.string()).nullable().optional(),
  expiration_at_ms: z.number().int().nullable().optional(),
  /** BILLING_ISSUE で、請求猶予期間の終了日時 */
  grace_period_expiration_at_ms: z.number().int().nullable().optional(),
  /** TRANSFER で、entitlement を失う側と受け取る側 */
  transferred_from: z.array(z.string()).nullable().optional(),
  transferred_to: z.array(z.string()).nullable().optional(),
});
export type RevenueCatEvent = z.infer<typeof revenueCatEventSchema>;

export const revenueCatWebhookBodySchema = z.object({
  api_version: z.string().optional(),
  event: revenueCatEventSchema,
});

/** RevenueCat SDK が付ける匿名 App User ID (IdentityManager.anonymousRegex と同じ) */
const anonymousAppUserIdPattern = /^\$RCAnonymousID:[a-z0-9]{32}$/;

export function isAnonymousAppUserId(appUserId: string): boolean {
  return anonymousAppUserIdPattern.test(appUserId);
}

/**
 * イベントが指す Firebase Auth の uid。
 * アプリは匿名認証の完了後に `Purchases.logIn(uid)` を呼ぶため、通常は app_user_id がそのまま uid。
 * logIn 前 (匿名 ID) のイベントは aliases に uid があればそれを使い、無ければ結び付ける相手がいないので null
 */
export function resolveUid(event: Pick<RevenueCatEvent, "app_user_id" | "aliases">): string | null {
  const candidates = [event.app_user_id, ...(event.aliases ?? [])];
  for (const candidate of candidates) {
    if (candidate && !isAnonymousAppUserId(candidate)) {
      return candidate;
    }
  }
  return null;
}

/** 1 ユーザーのプランをこの状態に更新する指示 */
export interface PlanUpdate {
  uid: string;
  plan: Plan;
  /** plan が pro の間の失効日時。null は期限なし。free では null */
  proExpiresAt: Date | null;
}

/**
 * pro entitlement を持つイベントが示す失効日時。
 * 請求猶予期間中は expiration_at_ms を過ぎてもアクセスが続くため、猶予期間の終了日時が後ならそちらを使う
 * (iOS 側の effectiveExpirationDate と同じ扱い)。どちらも無ければ期限なし
 */
function expiresAtOf(event: RevenueCatEvent): Date | null {
  const candidates = [event.expiration_at_ms, event.grace_period_expiration_at_ms].filter(
    (value): value is number => typeof value === "number",
  );
  if (candidates.length === 0) {
    return null;
  }
  return new Date(Math.max(...candidates));
}

/** 失効日時を過ぎた pro は free として保存する (読み取り側の effectivePlan と同じ境界。失効日時ちょうどは失効済み) */
function proOrFree(uid: string, expiresAt: Date | null, now: Date): PlanUpdate {
  if (expiresAt !== null && expiresAt.getTime() <= now.getTime()) {
    return { uid, plan: "free", proExpiresAt: null };
  }
  return { uid, plan: "pro", proExpiresAt: expiresAt };
}

/**
 * webhook イベントから、更新すべきユーザーとプランを決める。
 * 更新対象が無いイベント (TEST・pro 以外の entitlement・匿名 ID だけのイベント) は空配列。
 *
 * - TRANSFER: 失う側を free にし、受け取る側を pro にする。TRANSFER には失効日時が載らないため受け取る側は期限なしで登録し、
 *   その後の RENEWAL / EXPIRATION (受け取った側の app_user_id で届く) で失効日時を持たせる
 * - それ以外: entitlement_ids に pro を含むイベントを、その時点の失効日時つきの pro (失効済みなら free) として反映する。
 *   イベント種別ごとの分岐は持たない。CANCELLATION (自動更新の停止) は失効日時まで pro のままで、
 *   EXPIRATION は失効日時が過去になるため free に落ちる。返金は失効日時が返金時刻に繰り上がるため同様に free になる
 *
 * 純粋関数であり、同じイベントから常に同じ更新を返す (webhook の再送を冪等に処理できる)
 */
export function planUpdatesOf(event: RevenueCatEvent, now: Date): PlanUpdate[] {
  if (event.type === "TEST") {
    return [];
  }
  if (event.type === "TRANSFER") {
    const losing = (event.transferred_from ?? []).filter((id) => !isAnonymousAppUserId(id));
    const receiving = (event.transferred_to ?? []).filter((id) => !isAnonymousAppUserId(id));
    return [
      ...losing.map((uid): PlanUpdate => ({ uid, plan: "free", proExpiresAt: null })),
      ...receiving.map((uid): PlanUpdate => ({ uid, plan: "pro", proExpiresAt: null })),
    ];
  }
  if (!(event.entitlement_ids ?? []).includes(PRO_ENTITLEMENT_ID)) {
    return [];
  }
  const uid = resolveUid(event);
  if (uid === null) {
    return [];
  }
  return [proOrFree(uid, expiresAtOf(event), now)];
}
