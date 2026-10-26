/** 本番の Firebase プロジェクト ID。`firebase/.firebaserc` の prod alias と同じ値 */
const PROD_PROJECT_ID = "alarmify-prod";

/**
 * 実行中のプロジェクト ID に対応する、予算アラート・お問い合わせの投稿先 Slack チャンネル。
 * 本番のプロジェクトと判定できた時だけ slack-notification-setup skill の規約で作った「サービス名-notification」を返し、
 * それ以外 (dev・QA・ローカル・プロジェクト ID が取れない時) は「サービス名-notification-qa」に倒して、QA の投稿を本番の通知に混ぜない
 * (規約: bannzai/castle の home/.claude/documents/rules/qa-notifications-to-separate-channel.md)。
 * Crashlytics のアラートは skill が生成する crashlyticsAlert.ts の crashlyticsSlackChannel が同じ判定を持つ
 */
export function notificationSlackChannel(projectId: string): string {
  return projectId === PROD_PROJECT_ID ? "#alarmify-notification" : "#alarmify-notification-qa";
}
