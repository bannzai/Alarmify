import { z } from "zod";
import { timestampSchema } from "./firestore.js";

/**
 * users/{uid}/apiTokens/{tokenId}
 * 平文のトークンは保存しない。SHA-256 のハッシュと表示用のプレフィックスだけを持つ
 */
export const apiTokenSchema = z.object({
  name: z.string().min(1).max(64),
  hash: z.string().length(64),
  prefix: z.string().min(1),
  createdAt: timestampSchema,
  lastUsedAt: timestampSchema.nullable(),
  revokedAt: timestampSchema.nullable(),
});
export type ApiToken = z.infer<typeof apiTokenSchema>;
