import { initializeApp } from "firebase-admin/app";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { deleteUserAccount, sweepDeletedAccounts } from "./account/deleteAccount";

initializeApp();

/** Firestore・Functions ともに asia-northeast1 (ADR 0001) */
const region = "asia-northeast1";

/**
 * 呼び出し元自身のアカウントとサーバー上のデータを削除する Callable。
 * App Store Review Guideline 5.1.1 (v) の「アプリ内からのアカウント削除」に対応する。
 *
 * 認証は Firebase Auth (匿名認証) の ID トークンで行い、削除対象は必ずトークンの uid にする
 * (他人の uid を指定できないよう、リクエストのパラメータからは uid を受け取らない)。
 * App Check の強制はアプリ側の App Attest 導入と合わせて有効にする
 */
export const deleteAccount = onCall({ region }, async (request) => {
  const uid = request.auth?.uid;
  if (uid === undefined) {
    throw new HttpsError("unauthenticated", "Authentication is required to delete the account.");
  }

  const result = await deleteUserAccount(uid);
  return { userId: uid, ...result };
});

/**
 * アカウント削除の掃除が途中で失敗した分を完了させる定期実行。
 * 呼び出し元は Auth のユーザーが無くなると再試行できないため、サーバー側の信頼できる経路で残りを消す。
 * デプロイには Cloud Scheduler の権限が要る (documents/functions-deploy.md の `--scheduler`)
 */
export const sweepDeletedAccountsHourly = onSchedule({ region, schedule: "every 60 minutes" }, async () => {
  const result = await sweepDeletedAccounts(100);
  if (result.failed > 0) {
    throw new Error(`${result.failed} deleted account(s) could not be swept`);
  }
});
