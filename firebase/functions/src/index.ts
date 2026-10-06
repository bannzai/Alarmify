// 全関数の global options (実行 SA・region)。関数を定義するモジュールより先に評価させるため最初に import する
import "./globalOptions.js";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onCall, onRequest } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onMessagePublished } from "firebase-functions/pubsub";
import { onSchedule } from "firebase-functions/scheduler";
import {
  authUserExists,
  authUserProviderIds,
  completePendingAccountMerges,
  deleteUserAccount,
  handleDeleteAccount,
  sweepDeletedAccounts,
} from "./account/deleteAccount.js";
import { createAppApi } from "./api/appApi.js";
import { createExternalApi } from "./api/externalApi.js";
import { createRevenueCatWebhook } from "./api/revenueCatWebhook.js";
import { BUDGET_PUBSUB_TOPIC, createSlackPoster, notifyBudgetThreshold } from "./lib/budgetAlert.js";
import { deleteExpiredAlarms, EXPIRED_ALARMS_OUTLIVED_TTL_EVENT } from "./lib/cleanup.js";
import { parseAppCheckEnforcementMode } from "./lib/appCheck.js";
import type { Deps } from "./lib/deps.js";
import { createFcmPushSender, parsePushDeliveryMode } from "./lib/push.js";

initializeApp();

/**
 * 通知 bot (slack-notification-setup skill) の Slack bot token (Secret Manager)。
 * 登録手順は documents/budget-alert-slack.md。未登録だと deploy が止まる (defineSecret の仕様)
 */
const slackBotToken = defineSecret("SLACK_BOT_TOKEN");

function createDeps(): Deps {
  return {
    firestore: getFirestore(),
    sendPush: createFcmPushSender(getMessaging()),
    verifyIdToken: async (idToken) => {
      const decoded = await getAuth().verifyIdToken(idToken);
      return { uid: decoded.uid, signInProvider: decoded.firebase.sign_in_provider };
    },
    verifyAppCheckToken: async (appCheckToken) => {
      const verified = await getAppCheck().verifyToken(appCheckToken);
      return { appId: verified.appId };
    },
    // 監視のみ (monitor) から強制 (enforce) へ段階的に切り替える。値は firebase/functions/.env.<プロジェクト ID>
    appCheckEnforcementMode: () => parseAppCheckEnforcementMode(process.env.ALARMIFY_APP_CHECK_ENFORCEMENT),
    authUserExists: (uid) => authUserExists(getAuth(), uid),
    authUserProviderIds: (uid) => authUserProviderIds(getAuth(), uid),
    deleteUserAccount: (uid) => deleteUserAccount({ firestore: getFirestore(), auth: getAuth() }, uid),
    // 配送経路は #13 の実機検証で確定する。それまでは環境変数で切り替えられるようにする
    pushDeliveryMode: () => parsePushDeliveryMode(process.env.ALARMIFY_PUSH_DELIVERY),
    // token は投稿する時にだけ読む。SLACK_BOT_TOKEN を束ねていない関数 (alarmsApi 等) からは呼ばない
    postSlackMessage: createSlackPoster(() => slackBotToken.value()),
    // Cloud Functions のランタイムが実行中のプロジェクト ID を渡す
    projectId: () => process.env.GCLOUD_PROJECT ?? "",
    now: () => new Date(),
  };
}

/** アプリ向け API (Firebase Auth の ID トークンで認証)。お問い合わせを Slack へ通知するため SLACK_BOT_TOKEN を束ねる */
export const appApi = onRequest({ secrets: [slackBotToken] }, createAppApi(createDeps()));

/** 外部サービス向け API (Bearer = API トークン) */
export const alarmsApi = onRequest(createExternalApi(createDeps()));

/**
 * RevenueCat Dashboard の webhook 設定に登録した Authorization ヘッダーの値 (Secret Manager)。
 * 登録手順は documents/revenuecat-webhook.md。未登録だと deploy が止まる (defineSecret の仕様)
 */
const revenueCatWebhookAuthorization = defineSecret("REVENUECAT_WEBHOOK_AUTHORIZATION");

/** RevenueCat の webhook。entitlement pro の状態を users/{uid}.plan に反映する */
export const revenueCatWebhook = onRequest(
  { secrets: [revenueCatWebhookAuthorization] },
  createRevenueCatWebhook(createDeps(), { authorization: () => revenueCatWebhookAuthorization.value() }),
);

/**
 * TTL ポリシーが消し残した期限切れのアラーム要求の削除 (予備の経路。ADR 0008)。
 * TTL の猶予 (CLEANUP_TTL_GRACE_HOURS) より細かく回しても消し残しは増えないため 1 日 1 回にする。
 * 消し残しがあった時の error ログの `event` フィールドは Monitoring のアラートポリシー
 * (firebase/monitoring/expired-alarms-outlived-ttl.policy.json) のフィルタ条件なので変えない。
 * メッセージ文字列を条件にしないのは、firebase-functions の logger.error が severity ERROR の
 * message にスタックトレースを付ける (`Error: <message>\n    at ...`) ため、完全一致で拾えないから
 */
export const cleanupExpiredAlarms = onSchedule("every 24 hours", async () => {
  const deleted = await deleteExpiredAlarms(createDeps());
  if (deleted > 0) {
    logger.error("expired alarms outlived the TTL policy", {
      event: EXPIRED_ALARMS_OUTLIVED_TTL_EVENT,
      deleted,
    });
    return;
  }
  logger.info("no expired alarms outlived the TTL policy", { deleted });
});

/**
 * 呼び出し元自身のアカウントとサーバー上のデータを削除する Callable。
 * App Store Review Guideline 5.1.1 (v) の「アプリ内からのアカウント削除」に対応する。
 *
 * enforceAppCheck が true なら無効・欠落した App Check トークンを firebase-functions が 401 で拒否し、
 * false なら検証の失敗を warn ログに残して通す (アプリ向け API の monitor と同じ扱い)。
 * Callable のオプションはモジュールの読み込み時 (デプロイ時) に決まるため、切り替えには再デプロイが要る
 */
export const deleteAccount = onCall(
  { enforceAppCheck: parseAppCheckEnforcementMode(process.env.ALARMIFY_APP_CHECK_ENFORCEMENT) === "enforce" },
  (request) => handleDeleteAccount({ firestore: getFirestore(), auth: getAuth() }, request),
);

/**
 * アカウント削除の掃除と、統合した匿名アカウントの削除が途中で失敗した分を完了させる定期実行。
 * 呼び出し元は Auth のユーザーが無くなる・匿名の ID トークンが期限切れになると再試行できないため、サーバー側の信頼できる経路で残りを消す
 */
export const sweepDeletedAccountsHourly = onSchedule("every 60 minutes", async () => {
  const deps = { firestore: getFirestore(), auth: getAuth() };
  // 統合した匿名アカウントの削除を先に完了させる。ここで置いた削除の目印は、Auth のユーザーが消えていれば次回以降の sweep が掃除を終える
  const merges = await completePendingAccountMerges(deps, new Date());
  const result = await sweepDeletedAccounts(deps, new Date());
  if (merges.failed > 0 || result.failed > 0) {
    throw new Error(
      `${result.failed} deleted account(s) could not be swept and ${merges.failed} account merge(s) could not be completed`,
    );
  }
});

/**
 * Cloud Billing の予算通知 (Pub/Sub) を Slack #alarmify-notification へ転送する。
 * 予算が受け付ける Monitoring の通知チャンネルは email 型だけのため、Pub/Sub 経由で流す (ADR 0007)
 */
export const budgetAlertToSlack = onMessagePublished(
  { topic: BUDGET_PUBSUB_TOPIC, secrets: [slackBotToken] },
  async (event) => {
    // data が JSON でない時は json の getter が例外を投げる。形式の判定は notifyBudgetThreshold に寄せる
    let data: unknown;
    try {
      data = event.data.message.json;
    } catch (_error) {
      data = undefined;
    }
    const outcome = await notifyBudgetThreshold(
      {
        firestore: getFirestore(),
        postSlackMessage: createSlackPoster(() => slackBotToken.value()),
        now: () => new Date(),
      },
      { data, attributes: event.data.message.attributes },
    );
    logger.info("budget notification", { outcome, messageId: event.data.message.messageId });
  },
);

// firebase-crashlytics-alert-setup begin (bannzai/castle の skill が管理する区間。手で編集しない)
export { crashlyticsNewFatalIssueToSlack, crashlyticsRegressionToSlack, crashlyticsVelocityToSlack } from "./lib/crashlyticsAlert";
// firebase-crashlytics-alert-setup end
