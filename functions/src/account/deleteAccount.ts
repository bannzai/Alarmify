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

  // recursiveDelete はドキュメント本体とすべてのサブコレクションを消す。
  // ドキュメントが存在しなくてもサブコレクションだけが残っている場合があるため、存在確認とは無関係に必ず実行する
  await firestore.recursiveDelete(userDocument);

  const authUserExisted = await deleteAuthUser(uid);
  logger.info("Deleted account", { uid, authUserExisted, userDocumentExisted: snapshot.exists });

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
