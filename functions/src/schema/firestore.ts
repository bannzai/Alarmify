import { Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

/** Firestore のコレクション名。文字列リテラルをコード内へ散らばらせない (.claude/rules/firestore-db-rules.md) */
export const collections = {
  users: "users",
  apiTokens: "apiTokens",
  devices: "devices",
  alarms: "alarms",
} as const;

export const timestampSchema = z.custom<Timestamp>(
  (value) => value instanceof Timestamp,
  { message: "Firestore の Timestamp が必要です" },
);
