import type { Firestore } from "firebase-admin/firestore";
import type { PushDeliveryMode, PushSender } from "./push.js";

/** ID トークンの検証結果のうち、この API が使う部分だけ */
export interface VerifiedIdToken {
  uid: string;
}

/**
 * API とスケジュール実行が依存する外部リソース。
 * テストはエミュレータの Firestore と偽の push 送信・ID トークン検証を差し込む
 */
export interface Deps {
  firestore: Firestore;
  sendPush: PushSender;
  verifyIdToken: (idToken: string) => Promise<VerifiedIdToken>;
  pushDeliveryMode: () => PushDeliveryMode;
  now: () => Date;
}
