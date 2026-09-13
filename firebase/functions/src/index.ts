import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions";
import { onCall, onRequest } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onMessagePublished } from "firebase-functions/pubsub";
import { onSchedule } from "firebase-functions/scheduler";
import { authUserExists, handleDeleteAccount, sweepDeletedAccounts } from "./account/deleteAccount.js";
import { createAppApi } from "./api/appApi.js";
import { createExternalApi } from "./api/externalApi.js";
import { createRevenueCatWebhook } from "./api/revenueCatWebhook.js";
import { BUDGET_PUBSUB_TOPIC, createSlackPoster, notifyBudgetThreshold } from "./lib/budgetAlert.js";
import { deleteExpiredAlarms } from "./lib/cleanup.js";
import { parseAppCheckEnforcementMode } from "./lib/appCheck.js";
import type { Deps } from "./lib/deps.js";
import { createFcmPushSender, parsePushDeliveryMode } from "./lib/push.js";

initializeApp();
/**
 * 全関数を実行専用サービスアカウントで動かす。既定の Compute Engine サービスアカウントはプロジェクトの Editor を持つため、
 * Firestore / FCM / Auth / Secret の読み取りに絞った SA へ分離する (SA の作成と付与は documents/functions-deploy.md)。
 * 本番プロジェクトは alarmify-prod だけなのでメールアドレスを固定する。`functions-runtime@` の省略記法は firebase-tools が
 * Functions API 向けにだけ展開し、Secret のアクセス権付与と Cloud Scheduler の OIDC には未展開のまま渡すため使わない。
 * エミュレータ (demo-alarmify) はこの値を使わない
 */
setGlobalOptions({
  region: "asia-northeast1",
  maxInstances: 10,
  serviceAccount: "functions-runtime@alarmify-prod.iam.gserviceaccount.com",
});

function createDeps(): Deps {
  return {
    firestore: getFirestore(),
    sendPush: createFcmPushSender(getMessaging()),
    verifyIdToken: async (idToken) => {
      const decoded = await getAuth().verifyIdToken(idToken);
      return { uid: decoded.uid };
    },
    verifyAppCheckToken: async (appCheckToken) => {
      const verified = await getAppCheck().verifyToken(appCheckToken);
      return { appId: verified.appId };
    },
    // 監視のみ (monitor) から強制 (enforce) へ段階的に切り替える。値は firebase/functions/.env.<プロジェクト ID>
    appCheckEnforcementMode: () => parseAppCheckEnforcementMode(process.env.ALARMIFY_APP_CHECK_ENFORCEMENT),
    authUserExists: (uid) => authUserExists(getAuth(), uid),
    // 配送経路は #13 の実機検証で確定する。それまでは環境変数で切り替えられるようにする
    pushDeliveryMode: () => parsePushDeliveryMode(process.env.ALARMIFY_PUSH_DELIVERY),
    now: () => new Date(),
  };
}

/** アプリ向け API (Firebase Auth の ID トークンで認証) */
export const appApi = onRequest(createAppApi(createDeps()));

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

/** 保持期間を過ぎたアラーム要求の削除。期限切れの発生量を追い越せるよう、1 回の実行で複数バッチを処理する */
export const cleanupExpiredAlarms = onSchedule("every 6 hours", async () => {
  const deleted = await deleteExpiredAlarms(createDeps());
  logger.info("deleted expired alarms", { deleted });
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
 * アカウント削除の掃除が途中で失敗した分を完了させる定期実行。
 * 呼び出し元は Auth のユーザーが無くなると再試行できないため、サーバー側の信頼できる経路で残りを消す
 */
export const sweepDeletedAccountsHourly = onSchedule("every 60 minutes", async () => {
  const result = await sweepDeletedAccounts({ firestore: getFirestore(), auth: getAuth() }, new Date());
  if (result.failed > 0) {
    throw new Error(`${result.failed} deleted account(s) could not be swept`);
  }
});

/**
 * 通知 bot (slack-notification-setup skill) の Slack bot token (Secret Manager)。
 * 登録手順は documents/budget-alert-slack.md。未登録だと deploy が止まる (defineSecret の仕様)
 */
const slackBotToken = defineSecret("SLACK_BOT_TOKEN");

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
