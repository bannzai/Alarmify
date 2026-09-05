import type { Message, Messaging } from "firebase-admin/messaging";
import type { AlarmStatus } from "../schema/index.js";

/**
 * push の配送経路。どちらを本番採用するかは #13 の実機検証で確定する
 * - notification-service: visible push + mutable-content。Notification Service Extension が AlarmKit に登録する
 * - background: content-available の background push。app 本体が登録する
 */
export type PushDeliveryMode = "notification-service" | "background";

export const defaultPushDeliveryMode: PushDeliveryMode = "notification-service";

export function parsePushDeliveryMode(value: string | undefined): PushDeliveryMode {
  return value === "background" || value === "notification-service" ? value : defaultPushDeliveryMode;
}

export type AlarmAction = "schedule" | "cancel";

export function alarmActionOf(status: AlarmStatus): AlarmAction {
  return status === "canceled" ? "cancel" : "schedule";
}

export interface AlarmPushInput {
  fcmToken: string;
  id: string;
  action: AlarmAction;
  /** schedule では必須。cancel では null */
  fireAt: Date | null;
  title: string | null;
  mode: PushDeliveryMode;
}

export interface PushResult {
  successCount: number;
  failureCount: number;
  errors: string[];
}

export type PushSender = (messages: Message[]) => Promise<PushResult>;

/**
 * iOS の ISO8601DateFormatter (既定オプション) は小数秒を解釈しないため、秒までの ISO 8601 にする。
 * Date#toISOString がミリ秒を必ず含むので落とす
 */
export function toIso8601Seconds(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`;
}

/**
 * push payload を Alarmify/Shared/AlarmRequest.swift の形式 (`alarm` キー配下) に揃えて組み立てる。
 * FCM の data メッセージは値が文字列に限られるため、APNs の payload を直接指定する
 */
export function buildAlarmMessage(input: AlarmPushInput): Message {
  const alarm: Record<string, string> = { id: input.id, action: input.action };
  if (input.fireAt) {
    alarm.fire_at = toIso8601Seconds(input.fireAt);
  }
  if (input.title) {
    alarm.title = input.title;
  }

  const visible = input.mode === "notification-service";
  const body = input.action === "cancel" ? "アラームを取り消しました" : (input.title ?? "アラームを登録しました");

  return {
    token: input.fcmToken,
    apns: {
      headers: {
        "apns-push-type": visible ? "alert" : "background",
        "apns-priority": visible ? "10" : "5",
      },
      payload: {
        aps: visible
          ? { alert: { title: "Signalarm", body }, mutableContent: true, sound: "default" }
          : { contentAvailable: true },
        alarm,
      },
    },
  };
}

export function createFcmPushSender(messaging: Messaging): PushSender {
  return async (messages) => {
    if (messages.length === 0) {
      return { successCount: 0, failureCount: 0, errors: [] };
    }
    const response = await messaging.sendEach(messages);
    const errors = response.responses
      .filter((each) => !each.success)
      .map((each) => each.error?.code ?? "unknown");
    return {
      successCount: response.successCount,
      failureCount: response.failureCount,
      errors,
    };
  };
}
