import { z } from "zod";
import { timestampSchema } from "./firestore.js";

export const alarmStatusSchema = z.enum(["scheduled", "canceled"]);
export type AlarmStatus = z.infer<typeof alarmStatusSchema>;

export const alarmDeliverySchema = z.object({
  sentAt: timestampSchema.nullable(),
  successCount: z.number().int().nonnegative(),
  failureCount: z.number().int().nonnegative(),
  errors: z.array(z.string()),
});
export type AlarmDelivery = z.infer<typeof alarmDeliverySchema>;

export const deviceReportActionSchema = z.enum(["schedule", "cancel"]);
export type DeviceReportAction = z.infer<typeof deviceReportActionSchema>;

export const deviceReportResultSchema = z.enum(["applied", "failed"]);
export type DeviceReportResult = z.infer<typeof deviceReportResultSchema>;

/** 端末が AlarmRequest を AlarmKit へ反映した結果。users/{uid}/alarms/{alarmId}.deviceReports の値 (キーは device_id) */
export const deviceReportSchema = z.object({
  action: deviceReportActionSchema,
  result: deviceReportResultSchema,
  /** result が failed の時のエラーの説明。applied では null */
  error: z.string().nullable(),
  /** 端末が反映を行った時刻 (端末の時計) */
  occurredAt: timestampSchema,
  /** サーバーが報告を受け取った時刻 */
  reportedAt: timestampSchema,
});
export type DeviceReport = z.infer<typeof deviceReportSchema>;

/** users/{uid}/alarms/{alarmId}。alarmId は AlarmRequest.id と同じ UUID。expiresAt を過ぎたら削除する */
export const alarmSchema = z.object({
  title: z.string().nullable(),
  fireAt: timestampSchema,
  status: alarmStatusSchema,
  tokenId: z.string(),
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
  expiresAt: timestampSchema,
  delivery: alarmDeliverySchema,
  // 既存ドキュメントには無いフィールドのため optional。新規作成 (externalApi.ts の POST /v1/alarms) は {} で初期化する
  deviceReports: z.record(z.string(), deviceReportSchema).optional(),
});
export type Alarm = z.infer<typeof alarmSchema>;
