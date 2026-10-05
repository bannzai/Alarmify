import { z } from "zod";
import { timestampSchema } from "./firestore.js";

/** お問い合わせの種別。bannzai/Focus のお問い合わせフォームと同じ 3 種 */
export const contactInquiryTypeSchema = z.enum(["bug", "feedback", "other"]);
export type ContactInquiryType = z.infer<typeof contactInquiryTypeSchema>;

/**
 * contactInquiries/{自動採番 id}。
 * アプリのお問い合わせフォームから送られた問い合わせ。アカウントを削除しても対応の記録として残すため、
 * users/{uid} の下ではなくトップレベルに置き、expiresAt を過ぎたら Firestore の TTL ポリシーで消す
 * (保持期間は docs/AccountDeletion-ja.md の「お問い合わせは受信から 1 年間保持」)
 */
export const contactInquirySchema = z.object({
  /** 送信したアカウントの uid */
  uid: z.string().min(1),
  inquiryType: contactInquiryTypeSchema,
  content: z.string().min(1),
  /** 返信先のメールアドレス (ユーザーがフォームに入力した値) */
  emailAddress: z.string().min(1),
  /** 送信したアプリのバージョン (CFBundleShortVersionString)。取得できなかった時は null */
  appVersion: z.string().nullable(),
  createdAt: timestampSchema,
  /** TTL ポリシーの対象フィールド (firebase/firestore.indexes.json の fieldOverrides) */
  expiresAt: timestampSchema,
});
export type ContactInquiry = z.infer<typeof contactInquirySchema>;

/** contactInquiries/{id} のフィールド名。書き込み・テストはこの定数を通す */
export const contactInquiryFields = {
  uid: "uid",
  inquiryType: "inquiryType",
  content: "content",
  emailAddress: "emailAddress",
  appVersion: "appVersion",
  createdAt: "createdAt",
  expiresAt: "expiresAt",
} as const satisfies Record<keyof ContactInquiry, string>;
