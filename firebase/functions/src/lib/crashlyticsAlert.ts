/**
 * Crashlytics のアラート (新規 fatal issue / regression / velocity) を Slack の通知チャンネルへ転送する Cloud Functions (gen2)。
 * firebase-crashlytics-alert-setup skill (bannzai/castle) の setup-crashlytics-alert.sh が生成したファイル。
 * 手で編集した場合、再実行時は上書きせず [WARN] で知らせる (テンプレートの更新を取り込む時は一度削除して再生成する)。
 *
 * トリガーの仕様: https://firebase.google.com/docs/functions/alert-events
 * payload の型: firebase-functions の src/v2/providers/alerts/crashlytics.ts
 */
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";
import {
  onNewFatalIssuePublished,
  onRegressionAlertPublished,
  onVelocityAlertPublished,
} from "firebase-functions/v2/alerts/crashlytics";
import type {
  CrashlyticsEvent,
  Issue,
  NewFatalIssuePayload,
  RegressionAlertPayload,
  VelocityAlertPayload,
} from "firebase-functions/v2/alerts/crashlytics";

/**
 * 投稿先の Slack チャンネル。
 * slack-notification-setup skill の規約 (サービス名-notification) で作った通知チャンネルに揃える
 */
export const CRASHLYTICS_SLACK_CHANNEL = "#alarmify-notification";

/** slack-notification-setup skill の通知 bot の bot token (chat:write)。Secret Manager から起動時に読む */
const SLACK_BOT_TOKEN = defineSecret("SLACK_BOT_TOKEN");

/**
 * 3 つの関数に共通のオプション。region を省略すると firebase-functions の global options (無ければ us-east1) になる。
 * retry: Firebase Alerts トリガーは既定で再試行しないため、Slack のレート制限・一時障害・タイムアウトで関数が例外を投げた時に
 * Eventarc がイベントを再配送するよう有効にする (再配送された同じイベントは同じ本文を投稿する。投稿は成功したのに応答の受信で
 * 失敗した場合だけ二重投稿になり得るが、通知の喪失より許容できる)
 */
const FUNCTION_OPTIONS = { secrets: [SLACK_BOT_TOKEN], retry: true, region: "asia-northeast1" };

/** Slack API の応答は通常 1 秒以内のため、停滞の検知には 10 秒あれば足りる */
const SLACK_REQUEST_TIMEOUT_MS = 10_000;

export type CrashlyticsAlertKind = "newFatalIssue" | "regression" | "velocity";

/** Slack 本文の組み立てに使う入力。関数のイベントから取り出した値だけを持ち、テストでは直接組み立てられる */
export interface CrashlyticsAlertMessageInput {
  kind: CrashlyticsAlertKind;
  projectId: string;
  appId: string;
  issue: Issue;
  /** アラート種別ごとの補足 (velocity の件数・割合、regression の解決日時)。1 行に収める */
  detail?: string;
}

/** Firebase コンソールの issue 画面 */
export function crashlyticsIssueUrl(projectId: string, appId: string, issueId: string): string {
  return `https://console.firebase.google.com/project/${projectId}/crashlytics/app/${appId}/issues/${issueId}`;
}

/**
 * 分析を始めるためのコマンド。firebase-crashlytics-triage skill (bannzai/castle。整備は https://github.com/bannzai/castle/issues/1061 )
 * の引数の形に合わせる。同 skill の引数が変わった時はここを直す
 */
export function crashlyticsTriageCommand(appId: string, issueId: string): string {
  return `/firebase-crashlytics-triage --app-id ${appId} --issue-id ${issueId}`;
}

const KIND_HEADLINE: Record<CrashlyticsAlertKind, string> = {
  newFatalIssue: ":rotating_light: Crashlytics 新規の fatal issue",
  regression: ":repeat: Crashlytics regression (解決済み issue の再発)",
  velocity: ":chart_with_upwards_trend: Crashlytics velocity alert (クラッシュの急増)",
};

/** Slack へ投稿する本文。見出し・issue の title と subtitle・バージョン・補足・コンソール URL・分析コマンドを 1 通にまとめる */
export function formatCrashlyticsAlertText(input: CrashlyticsAlertMessageInput): string {
  const lines = [
    `${KIND_HEADLINE[input.kind]}: ${input.issue.title}`,
    input.issue.subtitle,
    `バージョン ${input.issue.appVersion} / app ${input.appId} / issue ${input.issue.id}`,
  ];
  if (input.detail) {
    lines.push(input.detail);
  }
  lines.push(crashlyticsIssueUrl(input.projectId, input.appId, input.issue.id));
  lines.push(`分析: ${crashlyticsTriageCommand(input.appId, input.issue.id)}`);
  return lines.join("\n");
}

/** 実行中の Firebase プロジェクト ID。Cloud Functions のランタイムが環境変数で渡す */
function currentProjectId(): string {
  const fromEnv = process.env.GCLOUD_PROJECT;
  if (fromEnv) {
    return fromEnv;
  }
  const firebaseConfig = process.env.FIREBASE_CONFIG;
  if (firebaseConfig) {
    const parsed = JSON.parse(firebaseConfig) as { projectId?: string };
    if (parsed.projectId) {
      return parsed.projectId;
    }
  }
  return "unknown-project";
}

/**
 * 再試行しても解消しない chat.postMessage のエラー (設定・権限の問題。https://api.slack.com/methods/chat.postMessage の Errors)。
 * これらは例外にせず記録だけして終える (retry: true のまま例外にすると、設定を直すまで Eventarc が再配送し続ける)
 */
const NON_RETRYABLE_SLACK_ERRORS = new Set([
  "not_in_channel",
  "channel_not_found",
  "is_archived",
  "invalid_auth",
  "token_revoked",
  "token_expired",
  "account_inactive",
  "missing_scope",
  "not_authed",
  "no_permission",
  "invalid_arguments",
  "msg_too_long",
  "no_text",
]);

/** 再試行で解消し得ない投稿失敗。forwardAlert が例外にせず記録だけして終えるための目印 */
export class SlackPermanentError extends Error {}

/**
 * Slack Web API の chat.postMessage で 1 件投稿する。
 * 一時的な失敗 (レート制限・5xx・タイムアウト・ネットワーク) は Error、設定起因の失敗は SlackPermanentError にする
 */
async function postToSlack(text: string): Promise<void> {
  const response = await fetch("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: {
      authorization: `Bearer ${SLACK_BOT_TOKEN.value()}`,
      "content-type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({ channel: CRASHLYTICS_SLACK_CHANNEL, text }),
    // 関数の実行時間の上限 (既定 60 秒) より十分に短くし、Slack が応答しない時も失敗として記録できるようにする
    signal: AbortSignal.timeout(SLACK_REQUEST_TIMEOUT_MS),
  });
  const body = (await response.json().catch(() => ({}))) as { ok?: boolean; error?: string };
  if (response.ok && body.ok === true) {
    return;
  }
  const reason = body.error ?? `HTTP ${response.status}`;
  if (body.error && NON_RETRYABLE_SLACK_ERRORS.has(body.error)) {
    throw new SlackPermanentError(`Slack chat.postMessage に失敗しました (設定を直すまで再試行しない): ${reason}`);
  }
  throw new Error(`Slack chat.postMessage に失敗しました: ${reason}`);
}

/**
 * 1 件のアラートを Slack へ転送する。
 * 一時的な失敗は例外を投げて Eventarc の再試行 (FUNCTION_OPTIONS.retry) に委ね、設定起因の失敗 (SlackPermanentError) は
 * 記録だけして正常終了する (再配送されても直らないため)。状態を持たないため、同じイベントが再配送されても同じ本文を投稿する
 */
async function forwardAlert(
  kind: CrashlyticsAlertKind,
  event: CrashlyticsEvent<{ issue: Issue }>,
  detail?: string,
): Promise<void> {
  const issue = event.data?.payload?.issue;
  if (!issue) {
    logger.warn("crashlytics alert has no issue in payload", { kind, appId: event.appId, eventId: event.id });
    return;
  }
  const context = { kind, appId: event.appId, issueId: issue.id, eventId: event.id };
  try {
    await postToSlack(
      formatCrashlyticsAlertText({ kind, projectId: currentProjectId(), appId: event.appId, issue, detail }),
    );
    logger.info("crashlytics alert forwarded to slack", context);
  } catch (error) {
    if (error instanceof SlackPermanentError) {
      logger.error("crashlytics alert forwarding failed permanently (fix slack settings)", { ...context, error: String(error) });
      return;
    }
    logger.error("crashlytics alert forwarding failed (will retry)", { ...context, error: String(error) });
    throw error;
  }
}

export const crashlyticsNewFatalIssueToSlack = onNewFatalIssuePublished(
  FUNCTION_OPTIONS,
  async (event: CrashlyticsEvent<NewFatalIssuePayload>) => {
    await forwardAlert("newFatalIssue", event);
  },
);

export const crashlyticsRegressionToSlack = onRegressionAlertPublished(
  FUNCTION_OPTIONS,
  async (event: CrashlyticsEvent<RegressionAlertPayload>) => {
    const payload = event.data?.payload;
    const detail = payload?.resolveTime ? `解決済みだった日時 ${payload.resolveTime} (種別 ${payload.type})` : undefined;
    await forwardAlert("regression", event, detail);
  },
);

export const crashlyticsVelocityToSlack = onVelocityAlertPublished(
  FUNCTION_OPTIONS,
  async (event: CrashlyticsEvent<VelocityAlertPayload>) => {
    const payload = event.data?.payload;
    // crashPercentage は API が返す値をそのまま載せる (割合か百分率かを firebase-functions の型定義が明示していないため換算しない)
    const detail = payload
      ? `crashCount ${payload.crashCount} / crashPercentage ${payload.crashPercentage} / 初出バージョン ${payload.firstVersion}`
      : undefined;
    await forwardAlert("velocity", event, detail);
  },
);
