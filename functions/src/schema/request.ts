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

/** push には秒までしか載せないため、小数秒は受け取った時点で切り捨てて以降の判定と揃える */
export const isoDateTimeSchema = z
  .string()
  .refine(isIsoDateTime, {
    message: "ISO 8601 の日時 (例: 2026-09-03T07:00:00Z) を指定してください",
  })
  .transform((value) => new Date(Math.floor(Date.parse(value) / 1000) * 1000));

const uuidPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * Firestore のドキュメント id は大文字小文字を区別するが、iOS 側の UUID は区別しない。
 * 同じアラームが 2 件登録されないよう、小文字に寄せてから使う
 */
export const canonicalUuidSchema = z
  .string()
  .regex(uuidPattern, { message: "id は UUID で指定してください" })
  .transform((value) => value.toLowerCase());

/**
 * 外部サービス向け: POST /v1/alarms
 * id は呼び出し側が付けるアラームの識別子。再送で同じ id が来た時に、二重登録せず同じアラームを返すために使う。
 * 発火時刻は fire_at (絶対時刻) か fire_in (受信からの秒数) のどちらか一方で指定する。
 * fire_in は、テンプレートで日時を計算できない連携先 (Grafana / Uptime Kuma / ショートカット等) のためにある (docs/api.md)
 */
export const createAlarmRequestSchema = z
  .object({
    id: canonicalUuidSchema.optional(),
    fire_at: isoDateTimeSchema.optional(),
    fire_in: z.number().int().min(0).optional(),
    title: z.string().min(1).max(200).optional(),
  })
  .refine((value) => (value.fire_at !== undefined) !== (value.fire_in !== undefined), {
    message: "fire_at と fire_in のどちらか一方を指定してください",
    path: ["fire_at"],
  });
export type CreateAlarmRequest = z.infer<typeof createAlarmRequestSchema>;

/** アプリ向け: POST /v1/devices */
export const registerDeviceRequestSchema = z.object({
  // Firestore のドキュメント id に "/" は使えない (パスとして解釈され、別の場所に保存されるか例外になる)
  device_id: z
    .string()
    .min(1)
    .max(128)
    .refine((value) => !value.includes("/"), { message: 'device_id に "/" は使えません' }),
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

/** アプリ向け: 一覧の続きを示す cursor (直前のページの最後の要素をエンコードした文字列) */
export const listCursorSchema = z.string().min(1).max(256).optional();
