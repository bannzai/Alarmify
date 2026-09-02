import { initializeApp } from "firebase-admin/app";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { deleteUserAccount } from "./account/deleteAccount";

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
