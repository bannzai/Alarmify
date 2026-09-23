import type { Firestore } from "firebase-admin/firestore";
import type { DeleteUserAccountResult } from "../account/deleteAccount.js";
import type { AppCheckEnforcementMode } from "./appCheck.js";
import type { PushDeliveryMode, PushSender } from "./push.js";

/** ID トークンの検証結果のうち、この API が使う部分だけ */
export interface VerifiedIdToken {
  uid: string;
  /** トークンを発行したサインイン方法 (ID トークンの `firebase.sign_in_provider`。匿名認証は "anonymous"、Sign in with Apple は "apple.com") */
  signInProvider: string;
}

/** App Check トークンの検証結果のうち、この API が使う部分だけ */
export interface VerifiedAppCheckToken {
  /** トークンを取得した Firebase アプリの ID */
  appId: string;
}

/**
 * API とスケジュール実行が依存する外部リソース。
 * テストはエミュレータの Firestore と偽の push 送信・ID トークン検証を差し込む
 */
export interface Deps {
  firestore: Firestore;
  sendPush: PushSender;
  verifyIdToken: (idToken: string) => Promise<VerifiedIdToken>;
  verifyAppCheckToken: (appCheckToken: string) => Promise<VerifiedAppCheckToken>;
  appCheckEnforcementMode: () => AppCheckEnforcementMode;
  /** Firebase Auth にユーザーが存在するか。RevenueCat の webhook が users/{uid} を作る前の確認に使う */
  authUserExists: (uid: string) => Promise<boolean>;
  /** アカウントのサーバー上のデータと Firebase Auth のユーザーを削除する (`deleteUserAccount`)。匿名アカウントの統合が使う */
  deleteUserAccount: (uid: string) => Promise<DeleteUserAccountResult>;
  pushDeliveryMode: () => PushDeliveryMode;
  now: () => Date;
}
