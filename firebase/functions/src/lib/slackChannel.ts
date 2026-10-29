/**
 * 本番の通知チャンネル。slack-notification-setup skill の規約 (サービス名-notification) で作ったチャンネルで、
 * 予算アラート・お問い合わせ・Crashlytics のアラート・Cloud Monitoring の error-log-spike アラートの宛先に揃える
 */
export const NOTIFICATION_SLACK_CHANNEL = "#alarmify-notification";

/**
 * bannzai のプロジェクト共通のテスト用チャンネル。テスト・QA で起こした投稿を本番の通知に混ぜないために使う
 * (規約: bannzai/castle の home/.claude/documents/rules/slack-test-notification-channel.md)
 */
export const TEST_NOTIFICATION_SLACK_CHANNEL = "#test-notification";

/**
 * お問い合わせの投稿先。リクエストにテスト用の引数 (`test: true`) が付いた時だけテスト用のチャンネル、それ以外は本番のチャンネル。
 * 実行中のプロジェクト ID では切り替えない (規約: 同上。dev のプロジェクトからでも引数が無い投稿は本番のチャンネルに送る)
 */
export function contactInquirySlackChannel(test: boolean): string {
  return test ? TEST_NOTIFICATION_SLACK_CHANNEL : NOTIFICATION_SLACK_CHANNEL;
}
