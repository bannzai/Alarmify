import { z } from "zod";
import { timestampSchema } from "./firestore.js";

/**
 * accountMerges/{匿名アカウントの uid}。
 * 匿名アカウントの端末を統合先 (Sign in with Apple のアカウント) へ移した時に置き、匿名アカウントの削除が済んだら消す。
 * 削除が途中で失敗し、アプリが送り直しに使う匿名の ID トークンが期限切れになっても、定期実行がこの記録を頼りに削除を完了させる
 */
export const accountMergeSchema = z.object({
  /** 端末を移した先のアカウントの uid */
  targetUid: z.string(),
  /** 端末を移した時刻。定期実行はこの値が十分に古い記録だけを対象にする */
  mergedAt: timestampSchema,
});
export type AccountMerge = z.infer<typeof accountMergeSchema>;

/** accountMerges/{uid} のフィールド名。書き込み・クエリ・テストはこの定数を通す */
export const accountMergeFields = {
  targetUid: "targetUid",
  mergedAt: "mergedAt",
} as const satisfies Record<keyof AccountMerge, string>;
