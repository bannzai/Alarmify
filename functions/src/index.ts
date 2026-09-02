import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions";
import { onRequest } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/scheduler";
import { createAppApi } from "./api/appApi.js";
import { createExternalApi } from "./api/externalApi.js";
import { deleteExpiredAlarms } from "./lib/cleanup.js";
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
    // 配送経路は #13 の実機検証で確定する。それまでは環境変数で切り替えられるようにする
    pushDeliveryMode: () => parsePushDeliveryMode(process.env.ALARMIFY_PUSH_DELIVERY),
    now: () => new Date(),
  };
}

/** アプリ向け API (Firebase Auth の ID トークンで認証) */
export const appApi = onRequest(createAppApi(createDeps()));

/** 外部サービス向け API (Bearer = API トークン) */
export const alarmsApi = onRequest(createExternalApi(createDeps()));

/** 保持期間を過ぎたアラーム要求の削除 */
export const cleanupExpiredAlarms = onSchedule("every 24 hours", async () => {
  const deleted = await deleteExpiredAlarms(createDeps());
  logger.info("deleted expired alarms", { deleted });
});
