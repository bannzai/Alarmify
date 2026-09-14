import {
  GrpcStatus,
  Timestamp,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import type { Deps } from "./deps.js";
import { collections } from "../schema/index.js";

/** 1 回の削除クエリで扱う件数 (.claude/rules/firestore-db-rules.md) */
export const CLEANUP_BATCH_SIZE = 500;
/** 1 回の実行で回すバッチ数の上限。TTL の消し残しを追い越せるだけ回し、無限に走らせない */
export const CLEANUP_MAX_BATCHES = 20;
/**
 * TTL ポリシーの削除を待つ猶予。これより古い期限切れは TTL が消し残したものとして扱う。
 * Firestore の TTL は「通常は期限から 24 時間以内に削除」(https://docs.cloud.google.com/firestore/native/docs/ttl) のため、その 2 倍を取る
 */
export const CLEANUP_TTL_GRACE_HOURS = 48;

/**
 * 問い合わせた時点から変わっていないドキュメントだけを削除する。
 * 問い合わせてから削除するまでの間に再スケジュールされたアラームを消さないよう、取得時点の更新時刻を条件にする
 * (条件に合わないものは残し、次回の実行の対象にする)
 */
export async function deleteUnchanged(
  firestore: Firestore,
  docs: QueryDocumentSnapshot[],
): Promise<number> {
  const writer = firestore.bulkWriter();
  writer.onWriteError(
    (error) => error.code !== GrpcStatus.FAILED_PRECONDITION && error.failedAttempts < 3,
  );
  // 個々の Promise は close() で書き込みが流れるまで解決しないため、先に積んでから close する
  const writes = docs.map((doc) =>
    writer.delete(doc.ref, { lastUpdateTime: doc.updateTime }).then(
      () => true,
      () => false,
    ),
  );
  await writer.close();
  return (await Promise.all(writes)).filter(Boolean).length;
}

export interface CleanupOptions {
  batchSize?: number;
  maxBatches?: number;
}

/**
 * TTL ポリシー (firebase/firestore.indexes.json の alarms / expiresAt) が消し残した期限切れのアラーム要求を削除する。
 * 保持期間を過ぎた文書の削除は TTL が担い、この関数は猶予を過ぎても残っている文書だけを消す予備の経路
 * (documents/adr/0008-delete-expired-alarms-with-firestore-ttl.md)。
 * 戻り値が 0 より大きいことが TTL の不調の目印になる。
 * 上限に達した場合は残りを次回の実行で処理する (再実行しても結果が変わらない)
 */
export async function deleteExpiredAlarms(
  deps: Deps,
  { batchSize = CLEANUP_BATCH_SIZE, maxBatches = CLEANUP_MAX_BATCHES }: CleanupOptions = {},
): Promise<number> {
  // WriteBatch の書き込み数の上限は 500 (Firestore の制限)。超えると commit が失敗して期限切れが残る
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > CLEANUP_BATCH_SIZE) {
    throw new RangeError(`batchSize は 1〜${CLEANUP_BATCH_SIZE} の整数で指定してください`);
  }
  if (!Number.isInteger(maxBatches) || maxBatches < 1 || maxBatches > CLEANUP_MAX_BATCHES) {
    throw new RangeError(`maxBatches は 1〜${CLEANUP_MAX_BATCHES} の整数で指定してください`);
  }
  const staleBefore = Timestamp.fromMillis(
    deps.now().getTime() - CLEANUP_TTL_GRACE_HOURS * 60 * 60 * 1000,
  );
  let deleted = 0;
  for (let batch = 0; batch < maxBatches; batch += 1) {
    const snapshot = await deps.firestore
      .collectionGroup(collections.alarms)
      .where("expiresAt", "<=", staleBefore)
      .limit(batchSize)
      .get();
    if (snapshot.empty) {
      break;
    }
    deleted += await deleteUnchanged(deps.firestore, snapshot.docs);
    if (snapshot.size < batchSize) {
      break;
    }
  }
  return deleted;
}
