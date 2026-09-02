import { z } from "zod";
import { devicePlatformSchema } from "./device.js";

/**
 * ISO 8601 (秒までの日時 + タイムゾーン) の文字列。
 * iOS 側の ISO8601DateFormatter (既定オプション) が解釈できる形式に合わせる
 */
const isoDateTimePattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

function isIsoDateTime(value: string): boolean {
  const match = isoDateTimePattern.exec(value);
  if (!match) {
    return false;
  }
  const [, year, month, day, hour, minute, second] = match.map(Number);
  // Date.parse は 2027-02-29 のような実在しない日付を翌月へ丸めてしまうため、暦日として実在するかを別に確かめる
  const normalized = new Date(Date.UTC(year, month - 1, day));
  if (
    normalized.getUTCFullYear() !== year ||
    normalized.getUTCMonth() !== month - 1 ||
    normalized.getUTCDate() !== day
  ) {
    return false;
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return false;
  }
  return !Number.isNaN(Date.parse(value));
}

export const isoDateTimeSchema = z
  .string()
  .refine(isIsoDateTime, {
    message: "ISO 8601 の日時 (例: 2026-09-03T07:00:00Z) を指定してください",
  })
  .transform((value) => new Date(value));

/** 外部サービス向け: POST /v1/alarms */
export const createAlarmRequestSchema = z.object({
  fire_at: isoDateTimeSchema,
  title: z.string().min(1).max(200).optional(),
});
export type CreateAlarmRequest = z.infer<typeof createAlarmRequestSchema>;

/** アプリ向け: POST /v1/devices */
export const registerDeviceRequestSchema = z.object({
  device_id: z.string().min(1).max(128),
  fcm_token: z.string().min(1).max(4096),
  platform: devicePlatformSchema.default("ios"),
});
export type RegisterDeviceRequest = z.infer<typeof registerDeviceRequestSchema>;

/** アプリ向け: POST /v1/api-tokens */
export const createApiTokenRequestSchema = z.object({
  name: z.string().min(1).max(64).default("default"),
});
export type CreateApiTokenRequest = z.infer<typeof createApiTokenRequestSchema>;

/** アプリ向け: GET /v1/alarms の limit。上限なしの取得を書かない (.claude/rules/firestore-db-rules.md) */
export const alarmHistoryLimitSchema = z.coerce.number().int().min(1).max(100).default(50);
