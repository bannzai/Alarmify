import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { deletedAccountDocumentPath, deletedAccountsCollectionId, userDocumentPath } from "../schema/user";

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
  const tombstone = firestore.doc(deletedAccountDocumentPath(uid));
  const snapshot = await userDocument.get();

  // recursiveDelete はドキュメント本体とすべてのサブコレクションを消す。
  // ドキュメントが存在しなくてもサブコレクションだけが残っている場合があるため、存在確認とは無関係に必ず実行する。
  // Auth のユーザーより先に消すのは、ここで失敗しても呼び出し元が同じ認証情報で再試行できるようにするため
  await firestore.recursiveDelete(userDocument);

  // Auth を消すとこの uid では再試行できなくなるため、その前に目印を置き、以降の失敗は sweepDeletedAccounts が引き継ぐ
  await tombstone.set({ requestedAt: FieldValue.serverTimestamp() });
  const authUserExisted = await deleteAuthUser(uid);

  // 1 回目の sweep と並行して届いた書き込み (配送先の登録等) を、この uid でサインインし直せなくなった後にもう一度消す。
  // これ以降に届き得るのは発行済みで未失効の ID トークンによる書き込みだけで、その窓はアプリ向け API の
  // 書き込み側が Auth のユーザーの存在を確認して拒否することで閉じる (バックエンド雛形の実装で担う)
  await firestore.recursiveDelete(userDocument);
  await tombstone.delete();

  // 削除したアカウントの識別子 (uid) はログにも残さない (ログの保持期間だけ識別可能なデータが残るため)
  logger.info("Deleted account", { authUserExisted, userDocumentExisted: snapshot.exists });

  return { authUserExisted, userDocumentExisted: snapshot.exists };
}

/**
 * Auth の削除後に掃除が途中で失敗したアカウント (`deletedAccounts/{uid}` が残っているもの) の削除を完了させる。
 * 1 回の実行で処理する件数に上限を設ける (.claude/rules/firestore-db-rules.md)。処理した件数を返す
 */
export async function sweepDeletedAccounts(limit: number): Promise<number> {
  const firestore = getFirestore();
  const tombstones = await firestore.collection(deletedAccountsCollectionId).limit(limit).get();
  for (const tombstone of tombstones.docs) {
    const uid = tombstone.id;
    await firestore.recursiveDelete(firestore.doc(userDocumentPath(uid)));
    await deleteAuthUser(uid);
    await tombstone.ref.delete();
  }
  if (tombstones.size > 0) {
    logger.info("Swept deleted accounts", { count: tombstones.size });
  }
  return tombstones.size;
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
