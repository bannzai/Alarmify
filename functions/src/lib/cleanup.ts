import { Timestamp } from "firebase-admin/firestore";
import type { Deps } from "./deps.js";
import { collections } from "../schema/index.js";

/** 1 回の削除クエリで扱う件数 (.claude/rules/firestore-db-rules.md) */
export const CLEANUP_BATCH_SIZE = 500;
/** 1 回の実行で回すバッチ数の上限。1 日の期限切れ件数を追い越せるだけ回し、無限に走らせない */
export const CLEANUP_MAX_BATCHES = 20;

export interface CleanupOptions {
  batchSize?: number;
  maxBatches?: number;
}

/**
 * 保持期間を過ぎたアラーム要求を削除する。
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
  let deleted = 0;
  for (let batch = 0; batch < maxBatches; batch += 1) {
    const snapshot = await deps.firestore
      .collectionGroup(collections.alarms)
      .where("expiresAt", "<=", Timestamp.fromDate(deps.now()))
      .limit(batchSize)
      .get();
    if (snapshot.empty) {
      break;
    }
    const writes = deps.firestore.batch();
    for (const doc of snapshot.docs) {
      writes.delete(doc.ref);
    }
    await writes.commit();
    deleted += snapshot.size;
    if (snapshot.size < batchSize) {
      break;
    }
  }
  return deleted;
}
