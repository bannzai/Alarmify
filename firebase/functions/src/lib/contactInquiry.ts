import type { ContactInquiryType } from "../schema/index.js";

/**
 * お問い合わせの通知先。slack-notification-setup skill の規約 (サービス名-notification) で作った通知チャンネルで、
 * 予算アラート・Crashlytics のアラートと同じ宛先に揃える
 */
export const CONTACT_INQUIRY_SLACK_CHANNEL = "#alarmify-notification";

/**
 * お問い合わせの保持期間 (日)。docs/AccountDeletion-ja.md の「お問い合わせは対応の記録として受信から 1 年間保持した後に削除」に合わせる
 */
export const CONTACT_INQUIRY_RETENTION_DAYS = 365;

/** Slack の通知に載せる種別の表示名。アプリのお問い合わせフォームの日本語の表示と揃える */
const INQUIRY_TYPE_LABEL: Record<ContactInquiryType, string> = {
  bug: "バグ・不具合",
  feedback: "ご意見・ご要望",
  other: "その他",
};

/**
 * Slack の mrkdwn で制御文字として扱われる `&` `<` `>` をエスケープする。
 * ユーザーが入力した本文の `<!channel>` やリンク記法を、そのまま通知に効かせないため
 * (https://docs.slack.dev/messaging/formatting-message-text#escaping )
 */
export function escapeSlackText(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Slack へ投稿する本文。種別・送信者・返信先・アプリのバージョン・Firestore の文書と、問い合わせの本文を 1 通にまとめる */
export function formatContactInquirySlackText(input: {
  projectId: string;
  inquiryId: string;
  uid: string;
  inquiryType: ContactInquiryType;
  content: string;
  emailAddress: string;
  appVersion: string | null;
}): string {
  return [
    ":mailbox_with_mail: 新規お問い合わせ",
    `[種別] ${INQUIRY_TYPE_LABEL[input.inquiryType]}`,
    `[UserID] ${escapeSlackText(input.uid)}`,
    `[Email] ${escapeSlackText(input.emailAddress)}`,
    `[AppVersion] ${input.appVersion === null ? "不明" : escapeSlackText(input.appVersion)}`,
    `[Firestore] https://console.firebase.google.com/project/${input.projectId}/firestore/databases/-default-/data/~2FcontactInquiries~2F${input.inquiryId}`,
    "━━━━━━━━━━━━━━━━━━━━",
    escapeSlackText(input.content),
    "━━━━━━━━━━━━━━━━━━━━",
  ].join("\n");
}
