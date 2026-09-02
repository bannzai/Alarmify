import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { userDocumentPath } from "../schema/user";

/**
 * アカウント削除の結果。削除前にアカウントが存在したかどうかを呼び出し元へ返す
 * (存在しない uid への削除も成功として扱うため、実際に消したかはこのフラグで判別する)
 */
export interface DeleteUserAccountResult {
  /** 削除前に Firebase Auth にユーザーが存在したか */
  authUserExisted: boolean;
  /** 削除前に `users/{uid}` のドキュメントが存在したか */
  userDocumentExisted: boolean;
}

/**
 * ユーザーのサーバー上のデータ (`users/{uid}` とその配下の apiTokens / devices / alarms) と
 * Firebase Auth のユーザーを削除する。
 *
 * 冪等: 既に削除済みの uid で再実行してもエラーにせず、削除済みの状態のまま結果を返す
 * (ネットワーク再送やユーザーの再タップで二重に呼ばれても成功で終わらせるため)
 */
export async function deleteUserAccount(uid: string): Promise<DeleteUserAccountResult> {
  const firestore = getFirestore();
  const userDocument = firestore.doc(userDocumentPath(uid));
  const snapshot = await userDocument.get();

  // 先に Auth のユーザーを消し、以後この uid で新しくサインイン・トークン更新できない状態にしてからデータを消す。
  // 発行済みで未失効の ID トークンによる書き込み (配送先の登録等) が残る窓は、アプリ向け API の書き込み側が
  // Auth のユーザーの存在を確認して拒否することで閉じる (バックエンド雛形の実装で担う)
  const authUserExisted = await deleteAuthUser(uid);

  // recursiveDelete はドキュメント本体とすべてのサブコレクションを消す。
  // ドキュメントが存在しなくてもサブコレクションだけが残っている場合があるため、存在確認とは無関係に必ず実行する
  await firestore.recursiveDelete(userDocument);

  // 削除したアカウントの識別子 (uid) はログにも残さない (ログの保持期間だけ識別可能なデータが残るため)
  logger.info("Deleted account", { authUserExisted, userDocumentExisted: snapshot.exists });

  return { authUserExisted, userDocumentExisted: snapshot.exists };
}

/** Firebase Auth のユーザーを削除する。既に存在しない場合は false を返して成功扱いにする */
async function deleteAuthUser(uid: string): Promise<boolean> {
  try {
    await getAuth().deleteUser(uid);
    return true;
  } catch (error) {
    if (isUserNotFound(error)) {
      return false;
    }
    throw error;
  }
}

function isUserNotFound(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: string }).code === "auth/user-not-found";
}
