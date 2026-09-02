/**
 * Firestore のユーザー配下のパス定義。
 * コレクション名の文字列リテラルを Functions とテストに散らばらせないため、参照はすべてここを通す
 * (.claude/rules/firestore-db-rules.md)。各ドキュメントのフィールド定義はバックエンド雛形の実装で追加する
 */

/** ユーザーのルートコレクション。1 ドキュメント = 1 アカウント (Firebase Auth の uid) */
export const usersCollectionId = "users";

/** `users/{uid}` 配下のサブコレクション。アカウント削除ではこれらをすべて消す */
export const userSubcollectionIds = {
  /** ハッシュ化した API トークン */
  apiTokens: "apiTokens",
  /** デバイストークン・プラットフォーム・最終確認日時 */
  devices: "devices",
  /** アラーム要求と配送状態 */
  alarms: "alarms",
} as const;

export type UserSubcollectionId = (typeof userSubcollectionIds)[keyof typeof userSubcollectionIds];

/** `users/{uid}` のドキュメントパス */
export function userDocumentPath(uid: string): string {
  return `${usersCollectionId}/${uid}`;
}

/** `users/{uid}/{subcollection}` のコレクションパス */
export function userSubcollectionPath(uid: string, subcollection: UserSubcollectionId): string {
  return `${userDocumentPath(uid)}/${subcollection}`;
}
