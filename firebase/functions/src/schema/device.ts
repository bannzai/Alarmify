import { z } from "zod";
import { timestampSchema } from "./firestore.js";

export const devicePlatformSchema = z.enum(["ios"]);
export type DevicePlatform = z.infer<typeof devicePlatformSchema>;

/** users/{uid}/devices/{deviceId}。deviceId はアプリが送る端末識別子 (identifierForVendor) */
export const deviceSchema = z.object({
  fcmToken: z.string().min(1),
  platform: devicePlatformSchema,
  createdAt: timestampSchema,
  updatedAt: timestampSchema,
});
export type Device = z.infer<typeof deviceSchema>;
