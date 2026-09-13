import type { DocumentData, DocumentReference, Firestore } from "firebase-admin/firestore";
import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { z } from "zod";
import { budgetNotificationSchema, collections, type BudgetNotification } from "../schema/index.js";

/**
 * Cloud Billing の予算通知を受ける Pub/Sub トピック名。
 * 予算 `budget-alarmify-prod` (gcp-alert-setup skill が作る displayName) と 1 対 1 なので同じ名前にする。
 * 予算への紐づけは documents/budget-alert-slack.md
 */
export const BUDGET_PUBSUB_TOPIC = "budget-alarmify-prod";

/**
 * 投稿先の Slack チャンネル。
 * slack-notification-setup skill の規約 (サービス名-notification) で作った通知チャンネルで、
 * Cloud Monitoring の error-log-spike アラートと同じ宛先に揃える
 */
export const BUDGET_SLACK_CHANNEL = "#alarmify-notification";

/**
 * 予算通知のメッセージ本文 (Pub/Sub の data を JSON にしたもの) のうち使う部分。
 * 形式: https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications
 * 閾値を超えていない時は alertThresholdExceeded / forecastThresholdExceeded が載らない
 */
export const budgetMessageSchema = z.object({
  budgetDisplayName: z.string().min(1),
  costAmount: z.number().nonnegative(),
  /** 集計期間の開始 (RFC 3339)。月次予算では月初 */
  costIntervalStart: z.string().min(1),
  budgetAmount: z.number().nonnegative(),
  /** 実績 (CURRENT_SPEND) の閾値ルールのうち、超えた最大のもの (0.5 = 50%) */
  alertThresholdExceeded: z.number().nonnegative().optional(),
  /** 予測 (FORECASTED_SPEND) の閾値ルールのうち、超えた最大のもの。予算 budget-alarmify-prod には予測ルールが無い */
  forecastThresholdExceeded: z.number().nonnegative().optional(),
  currencyCode: z.string().min(1),
});
export type BudgetMessage = z.infer<typeof budgetMessageSchema>;

/** 予算通知のメッセージ属性のうち使う部分 */
export const budgetMessageAttributesSchema = z.object({
  budgetId: z.string().min(1),
  billingAccountId: z.string().min(1).optional(),
});
export type BudgetMessageAttributes = z.infer<typeof budgetMessageAttributesSchema>;

/** 転送が依存する外部リソース。テストはエミュレータの Firestore と偽の Slack 投稿を差し込む */
export interface BudgetAlertDeps {
  firestore: Firestore;
  /** Slack のチャンネルへ本文を 1 件投稿する。投稿できなかった時は例外にする */
  postSlackMessage: (channel: string, text: string) => Promise<void>;
  now: () => Date;
}

/** 1 件の予算通知の処理結果。ログに載せる */
export type BudgetAlertOutcome =
  /** 閾値を新しく超えたので Slack へ投稿した */
  | "posted"
  /** どの閾値も超えていない通常の状態報告 */
  | "no_threshold"
  /** 同じ集計期間で同じ (またはより高い) 閾値を投稿済み */
  | "already_notified"
  /** 記録済みより古い集計期間の通知 (月替わり後に遅れて届いた前月分)。記録を巻き戻さない */
  | "stale_period"
  /** 予算通知の形式に合わない */
  | "invalid";

export function budgetNotificationRef(
  firestore: Firestore,
  budgetId: string,
): DocumentReference<DocumentData> {
  return firestore.collection(collections.budgetNotifications).doc(budgetId);
}

/** 金額を通貨つきで表示する。通貨コードが Intl に無い時はコードを添えて数値のまま出す */
function formatAmount(amount: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("ja-JP", { style: "currency", currency: currencyCode }).format(amount);
  } catch (_error) {
    return `${amount} ${currencyCode}`;
  }
}

/**
 * 通知の集計期間が記録済みの集計期間より前か。
 * どちらも RFC 3339 として解釈できる時だけ時刻で比べる (解釈できない値は「前ではない」として扱い、通常の判定に進める)
 */
function isEarlierInterval(storedIntervalStart: string, messageIntervalStart: string): boolean {
  const stored = Date.parse(storedIntervalStart);
  const incoming = Date.parse(messageIntervalStart);
  return !Number.isNaN(stored) && !Number.isNaN(incoming) && incoming < stored;
}

/** Slack へ投稿する本文。閾値・支出・予算・集計期間と、予算画面へのリンクを 1 通にまとめる */
export function formatBudgetSlackText(
  message: BudgetMessage,
  thresholdPercent: number,
  attributes: BudgetMessageAttributes,
): string {
  const lines = [
    `:warning: 予算アラート: ${message.budgetDisplayName} の支出が予算の ${Math.round(thresholdPercent * 100)}% を超えました`,
    `支出 ${formatAmount(message.costAmount, message.currencyCode)} / 予算 ${formatAmount(message.budgetAmount, message.currencyCode)} (集計開始 ${message.costIntervalStart})`,
  ];
  if (attributes.billingAccountId) {
    lines.push(`https://console.cloud.google.com/billing/${attributes.billingAccountId}/budgets`);
  }
  return lines.join("\n");
}

/**
 * Pub/Sub の予算通知を 1 件処理する。
 * 予算通知は閾値の超過に関係なく 1 日に複数回届き、超過後はどのメッセージにも同じ閾値が載るため、
 * 集計期間ごとに投稿済みの最大閾値を budgetNotifications/{budgetId} に覚え、閾値が上がった時だけ投稿する。
 * 記録は Slack への投稿が成功した後に書く (投稿に失敗した通知は記録が残らず、次の通知で投稿し直せる)。
 * 同じ予算の通知が同時に 2 件届くと二重投稿になり得るが、通知の間隔は数時間あるので競合の制御は持たない。
 * 同じ通知を何度受けても同じ状態に収束する (冪等)
 */
export async function notifyBudgetThreshold(
  deps: BudgetAlertDeps,
  input: { data: unknown; attributes: Record<string, string> },
): Promise<BudgetAlertOutcome> {
  const message = budgetMessageSchema.safeParse(input.data);
  const attributes = budgetMessageAttributesSchema.safeParse(input.attributes);
  if (!message.success || !attributes.success) {
    logger.warn("budget notification has unexpected format", {
      messageIssues: message.success ? [] : message.error.issues,
      attributeIssues: attributes.success ? [] : attributes.error.issues,
    });
    return "invalid";
  }
  const thresholdPercent = message.data.alertThresholdExceeded;
  if (thresholdPercent === undefined) {
    return "no_threshold";
  }

  const ref = budgetNotificationRef(deps.firestore, attributes.data.budgetId);
  const snapshot = await ref.get();
  const stored = snapshot.exists ? budgetNotificationSchema.safeParse(snapshot.data()) : null;
  if (stored?.success) {
    // Pub/Sub の配送順序に依存しない。前月の通知が月替わり後に遅れて届いても、今月の記録を前月で上書きしない
    if (isEarlierInterval(stored.data.costIntervalStart, message.data.costIntervalStart)) {
      return "stale_period";
    }
    if (
      stored.data.costIntervalStart === message.data.costIntervalStart &&
      stored.data.notifiedThresholdPercent >= thresholdPercent
    ) {
      return "already_notified";
    }
  }

  await deps.postSlackMessage(
    BUDGET_SLACK_CHANNEL,
    formatBudgetSlackText(message.data, thresholdPercent, attributes.data),
  );
  const record: BudgetNotification = {
    costIntervalStart: message.data.costIntervalStart,
    notifiedThresholdPercent: thresholdPercent,
    updatedAt: Timestamp.fromDate(deps.now()),
  };
  await ref.set(record);
  return "posted";
}

/**
 * Slack Web API の chat.postMessage で投稿する。
 * token は slack-notification-setup skill の通知 bot の bot token (Secret Manager から起動時に読むため関数で受け取る)
 */
export function createSlackPoster(token: () => string): BudgetAlertDeps["postSlackMessage"] {
  return async (channel, text) => {
    const response = await fetch("https://slack.com/api/chat.postMessage", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token()}`,
        "content-type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({ channel, text }),
    });
    const body = (await response.json()) as { ok?: boolean; error?: string };
    if (!response.ok || body.ok !== true) {
      throw new Error(`Slack chat.postMessage に失敗しました: ${body.error ?? `HTTP ${response.status}`}`);
    }
  };
}
