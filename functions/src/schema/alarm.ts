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
});
export type Alarm = z.infer<typeof alarmSchema>;
