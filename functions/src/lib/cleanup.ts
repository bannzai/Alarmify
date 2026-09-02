import { Timestamp } from "firebase-admin/firestore";
import type { Deps } from "./deps.js";
import { collections } from "../schema/index.js";

/** 1 回の実行で削除する上限 (.claude/rules/firestore-db-rules.md) */
export const CLEANUP_BATCH_LIMIT = 500;

/**
 * 保持期間 (30 日) を過ぎたアラーム要求を削除する。
 * 上限に達した場合は残りを次回の実行で処理する (再実行しても結果が変わらない)
 */
export async function deleteExpiredAlarms(
  deps: Deps,
  limit: number = CLEANUP_BATCH_LIMIT,
): Promise<number> {
  const snapshot = await deps.firestore
    .collectionGroup(collections.alarms)
    .where("expiresAt", "<=", Timestamp.fromDate(deps.now()))
    .limit(limit)
    .get();
  if (snapshot.empty) {
    return 0;
  }
  const batch = deps.firestore.batch();
  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();
  return snapshot.size;
}
