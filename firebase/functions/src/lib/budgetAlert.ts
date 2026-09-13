import type { DocumentData, DocumentReference, DocumentSnapshot, Firestore } from "firebase-admin/firestore";
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
  /** 予算の ID (UUID)。Firestore のドキュメント ID に使うため、パス区切りになる `/` を含む値は受け付けない */
  budgetId: z.string().min(1).regex(/^[^/]+$/),
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
 * 記録は Slack への投稿が成功した後に、前へ進める方向にだけ書く (投稿に失敗した通知は記録が残らず、次の通知で投稿し直せる)。
 * 同じ予算の通知が同時に 2 件届くと二重投稿になり得るが、通知の間隔は数時間あり、投稿前に記録を確保する設計は
 * Slack が失敗した通知を取りこぼすため、投稿の競合の制御は持たない (記録の巻き戻りだけをトランザクションで防ぐ)。
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

  const context = {
    budgetId: attributes.data.budgetId,
    costIntervalStart: message.data.costIntervalStart,
    thresholdPercent,
  };
  const ref = budgetNotificationRef(deps.firestore, attributes.data.budgetId);
  try {
    const stored = readRecord(await ref.get());
    if (stored && !advancesRecord(stored, message.data.costIntervalStart, thresholdPercent)) {
      return isEarlierInterval(stored.costIntervalStart, message.data.costIntervalStart)
        ? "stale_period"
        : "already_notified";
    }

    await deps.postSlackMessage(
      BUDGET_SLACK_CHANNEL,
      formatBudgetSlackText(message.data, thresholdPercent, attributes.data),
    );

    // 記録は前へ進める方向にだけ書く。投稿と記録の間に別の通知が先に記録していても、高い閾値・新しい期間を低い方で上書きしない
    await deps.firestore.runTransaction(async (transaction) => {
      const current = readRecord(await transaction.get(ref));
      if (current && !advancesRecord(current, message.data.costIntervalStart, thresholdPercent)) {
        return;
      }
      const record: BudgetNotification = {
        costIntervalStart: message.data.costIntervalStart,
        notifiedThresholdPercent: thresholdPercent,
        updatedAt: Timestamp.fromDate(deps.now()),
      };
      transaction.set(ref, record);
    });
    return "posted";
  } catch (error) {
    // 失敗した通知は記録が残らず次の通知で投稿し直す。原因を追えるよう、どの予算・期間・閾値で失敗したかを残す
    logger.error("budget notification failed", { ...context, error: String(error) });
    throw error;
  }
}

/** 保存済みの記録。形式が合わない (手で書き換えた等) 記録は無い扱いにして、通常の判定へ進める */
function readRecord(snapshot: DocumentSnapshot): BudgetNotification | null {
  if (!snapshot.exists) {
    return null;
  }
  const parsed = budgetNotificationSchema.safeParse(snapshot.data());
  return parsed.success ? parsed.data : null;
}

/**
 * 通知が記録を前へ進めるか。
 * 同じ期間なら閾値が上がった時、記録より新しい期間ならその時だけ true。記録より古い期間・同じ期間の同じ以下の閾値は false
 */
function advancesRecord(stored: BudgetNotification, costIntervalStart: string, thresholdPercent: number): boolean {
  if (isEarlierInterval(stored.costIntervalStart, costIntervalStart)) {
    return false;
  }
  if (stored.costIntervalStart === costIntervalStart) {
    return thresholdPercent > stored.notifiedThresholdPercent;
  }
  return true;
}

/** Slack API の応答は通常 1 秒以内のため、停滞の検知には 10 秒あれば足りる */
const SLACK_REQUEST_TIMEOUT_MS = 10_000;

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
      // 関数の実行時間の上限 (既定 60 秒) より十分に短くし、Slack が応答しない時も上限で強制終了されずに失敗として記録できるようにする
      signal: AbortSignal.timeout(SLACK_REQUEST_TIMEOUT_MS),
    });
    const body = (await response.json()) as { ok?: boolean; error?: string };
    if (!response.ok || body.ok !== true) {
      throw new Error(`Slack chat.postMessage に失敗しました: ${body.error ?? `HTTP ${response.status}`}`);
    }
  };
}
