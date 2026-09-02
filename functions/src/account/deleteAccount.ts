import type { Auth } from "firebase-admin/auth";
import { FieldValue, type DocumentReference, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { collections, deletedAccountFields } from "../schema/index.js";

/** アカウント削除が依存する外部リソース。テストはエミュレータの Firestore / Auth を差し込む */
export interface AccountDeletionDeps {
  firestore: Firestore;
  auth: Pick<Auth, "deleteUser" | "getUser">;
}

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
 * 目印を置いてからこの時間が経つまでは sweep が触れず、目印が残り続ける。
 * 目印がある間はアプリ向け API の書き込みが拒否されるため、削除前に発行された ID トークン (有効期間 1 時間) による
 * 書き込みがデータを作り直せない。2 時間経てば有効な ID トークンは残らず、sweep が最後の掃除をして目印を消す
 */
export const DELETION_MARKER_MINIMUM_AGE_MS = 2 * 60 * 60 * 1000;

/** 1 回の sweep で処理する目印の件数の上限 (.claude/rules/firestore-db-rules.md) */
export const SWEEP_BATCH_SIZE = 100;

/**
 * ユーザーのサーバー上のデータ (`users/{uid}` とその配下の apiTokens / devices / alarms) と
 * Firebase Auth のユーザーを削除する。
 *
 * 冪等: 既に削除済みの uid で再実行してもエラーにせず、削除済みの状態のまま結果を返す
 * (ネットワーク再送やユーザーの再タップで二重に呼ばれても成功で終わらせるため)
 */
export async function deleteUserAccount(
  deps: AccountDeletionDeps,
  uid: string,
): Promise<DeleteUserAccountResult> {
  const userDocument = deps.firestore.collection(collections.users).doc(uid);
  const tombstone = deps.firestore.collection(collections.deletedAccounts).doc(uid);
  const snapshot = await userDocument.get();

  // 削除の確定点は Auth のユーザーの削除で、データはその後に消す。
  // Auth より先にデータを消すと、Auth の削除に失敗した時に「アカウントは生きているのにデータだけ消えた」状態で
  // 呼び出し元へエラーを返すことになるため、Auth が消えるまでは何も壊さない。
  // Auth を消すとこの uid では再試行できなくなるため、その前に目印を置き、以降の失敗は sweepDeletedAccounts が引き継ぐ。
  // Auth の削除がエラーで終わっても目印はそのまま残す。応答が失われただけで削除は済んでいる可能性があり、
  // sweep が Auth の有無を見て、残っていれば取り下げ・消えていれば掃除を完了させる
  await tombstone.set({ [deletedAccountFields.requestedAt]: FieldValue.serverTimestamp() });
  const authUserExisted = await deleteAuthUserOrWithdrawMarker(deps, uid, tombstone);

  // recursiveDelete はドキュメント本体とすべてのサブコレクションを消す。
  // ドキュメントが存在しなくてもサブコレクションだけが残っている場合があるため、存在確認とは無関係に必ず実行する。
  // 目印はここでは消さない。削除前に発行された ID トークンによる書き込みが後から届いても、
  // 目印がある間はアプリ向け API が拒否し、目印は有効な ID トークンが残らなくなった後に sweep が最後の掃除と一緒に消す
  await deps.firestore.recursiveDelete(userDocument);

  // 削除したアカウントの識別子 (uid) はログにも残さない (ログの保持期間だけ識別可能なデータが残るため)
  logger.info("deleted account", { authUserExisted, userDocumentExisted: snapshot.exists });

  return { authUserExisted, userDocumentExisted: snapshot.exists };
}

/** sweepDeletedAccounts の処理結果 */
export interface SweepDeletedAccountsResult {
  /** 配下のデータを消して目印を外した件数 */
  completed: number;
  /** Auth のユーザーが残っていたため、目印だけ取り下げた件数 */
  withdrawn: number;
  /** 失敗して次回に持ち越した件数 */
  failed: number;
}

/**
 * Auth の削除後に掃除が途中で失敗したアカウント (`deletedAccounts/{uid}` が残っているもの) の削除を完了させる。
 * Auth のユーザーがまだ存在する目印は、削除が確定する前に失敗したものなので、データに触れずに目印だけ取り下げる。
 * 1 件の失敗で残りを止めない (失敗した目印は次回の実行でまた対象になる)
 */
export async function sweepDeletedAccounts(
  deps: AccountDeletionDeps,
  now: Date,
  limit: number = SWEEP_BATCH_SIZE,
): Promise<SweepDeletedAccountsResult> {
  const tombstones = await deps.firestore
    .collection(collections.deletedAccounts)
    .where(deletedAccountFields.requestedAt, "<=", new Date(now.getTime() - DELETION_MARKER_MINIMUM_AGE_MS))
    .limit(limit)
    .get();
  const result: SweepDeletedAccountsResult = { completed: 0, withdrawn: 0, failed: 0 };
  for (const tombstone of tombstones.docs) {
    const uid = tombstone.id;
    try {
      // 目印はこの実行が読んだ版に限って消す。読んだ後に Callable の再試行が目印を置き直していたら
      // (updateTime が変わる) 消さずに失敗として扱い、その再試行の目印を残す
      const staleVersionOnly = { lastUpdateTime: tombstone.updateTime };
      if (await authUserExists(deps.auth, uid)) {
        await tombstone.ref.delete(staleVersionOnly);
        result.withdrawn += 1;
        continue;
      }
      await deps.firestore.recursiveDelete(deps.firestore.collection(collections.users).doc(uid));
      await tombstone.ref.delete(staleVersionOnly);
      result.completed += 1;
    } catch (error) {
      result.failed += 1;
      logger.error("sweeping a deleted account failed", { error: String(error) });
    }
  }
  if (tombstones.size > 0) {
    logger.info("swept deleted accounts", result);
  }
  return result;
}

/**
 * Callable `deleteAccount` の本体。呼び出し元自身のアカウントを削除する。
 * 削除対象は必ず ID トークンの uid にする (他人の uid を指定できないよう、リクエストのパラメータからは uid を受け取らない)
 */
export async function handleDeleteAccount(
  deps: AccountDeletionDeps,
  // CallableRequest のうち使うのは認証情報の uid だけ (テストが request 全体を組み立てなくて済むようにする)
  request: { auth?: { uid: string } },
): Promise<DeleteUserAccountResult & { userId: string }> {
  const uid = request.auth?.uid;
  if (uid === undefined) {
    throw new HttpsError("unauthenticated", "Authentication is required to delete the account.");
  }
  const result = await deleteUserAccount(deps, uid);
  return { userId: uid, ...result };
}

/**
 * Auth のユーザーを削除する。削除がエラーで終わった時は、ユーザーが残っているかを確かめて目印の扱いを決める:
 * 残っていることが確認できたら削除は確定していないので目印を外してからエラーを返す
 * (目印がある間は書き込みが拒否されるため、生きているアカウントを最大 3 時間止めない)。
 * 消えていることが確認できたら応答が失われただけなので削除済みとして進める。確認もできなければ目印を残してエラーを返す
 */
async function deleteAuthUserOrWithdrawMarker(
  deps: AccountDeletionDeps,
  uid: string,
  tombstone: DocumentReference,
): Promise<boolean> {
  try {
    return await deleteAuthUser(deps.auth, uid);
  } catch (error) {
    let stillExists: boolean;
    try {
      stillExists = await authUserExists(deps.auth, uid);
    } catch {
      throw error;
    }
    if (!stillExists) {
      return true;
    }
    await tombstone.delete();
    throw error;
  }
}

/** Firebase Auth のユーザーを削除する。既に存在しない場合は false を返して成功扱いにする */
async function deleteAuthUser(auth: AccountDeletionDeps["auth"], uid: string): Promise<boolean> {
  try {
    await auth.deleteUser(uid);
    return true;
  } catch (error) {
    if (isUserNotFound(error)) {
      return false;
    }
    throw error;
  }
}

/** Firebase Auth にユーザーが存在するか */
async function authUserExists(auth: AccountDeletionDeps["auth"], uid: string): Promise<boolean> {
  try {
    await auth.getUser(uid);
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
