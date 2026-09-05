import { z } from "zod";
import { timestampSchema } from "./firestore.js";

/**
 * deletedAccounts/{uid}。
 * アカウント削除の Callable が Auth のユーザーを消す前に置き、`users/{uid}` 配下の掃除まで終わったら消す。
 * 掃除が途中で失敗しても、定期実行の sweep がこの目印を頼りに完了させる (呼び出し元は Auth が無くなると再試行できないため)
 */
export const deletedAccountSchema = z.object({
  /** 目印を置いた時刻。sweep はこの値が十分に古い目印だけを対象にする */
  requestedAt: timestampSchema,
});
export type DeletedAccount = z.infer<typeof deletedAccountSchema>;

/** deletedAccounts/{uid} のフィールド名。書き込み・クエリ・テストはこの定数を通す */
export const deletedAccountFields = {
  requestedAt: "requestedAt",
} as const satisfies Record<keyof DeletedAccount, string>;
