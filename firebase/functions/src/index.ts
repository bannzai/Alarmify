import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions";
import { onCall, onRequest } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onSchedule } from "firebase-functions/scheduler";
import { authUserExists, handleDeleteAccount, sweepDeletedAccounts } from "./account/deleteAccount.js";
import { createAppApi } from "./api/appApi.js";
import { createExternalApi } from "./api/externalApi.js";
import { createRevenueCatWebhook } from "./api/revenueCatWebhook.js";
import { deleteExpiredAlarms } from "./lib/cleanup.js";
import { parseAppCheckEnforcementMode } from "./lib/appCheck.js";
import type { Deps } from "./lib/deps.js";
import { createFcmPushSender, parsePushDeliveryMode } from "./lib/push.js";

initializeApp();
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });

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
