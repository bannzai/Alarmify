import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/** 外部サービスが Bearer で送る API トークンの接頭辞 */
export const API_TOKEN_PREFIX = "alm_";
/** 表示用に保存する先頭部分の長さ (接頭辞 + 8 文字) */
const DISPLAY_PREFIX_LENGTH = API_TOKEN_PREFIX.length + 8;

export interface GeneratedApiToken {
  /** 平文。発行時に 1 度だけ返し、保存しない */
  token: string;
  /** SHA-256 のハッシュ (hex) */
  hash: string;
  /** 表示用の先頭部分 */
  prefix: string;
}

export function hashApiToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function displayPrefix(token: string): string {
  return token.slice(0, DISPLAY_PREFIX_LENGTH);
}

export function generateApiToken(): GeneratedApiToken {
  const token = `${API_TOKEN_PREFIX}${randomBytes(32).toString("base64url")}`;
  return { token, hash: hashApiToken(token), prefix: displayPrefix(token) };
}

/** ハッシュ同士の比較。長さが同じ hex 前提で、タイミング差を残さない */
export function hashEquals(a: string, b: string): boolean {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  if (left.length !== right.length) {
    return false;
  }
  return timingSafeEqual(left, right);
}

/**
 * 発行した平文トークンの形式。
 * 形式に合わないトークンは Firestore を引く前に弾く (認証前の読み取りを増やさないため)
 */
const apiTokenPattern = new RegExp(`^${API_TOKEN_PREFIX}[A-Za-z0-9_-]{43}$`);

export function isApiTokenFormat(token: string): boolean {
  return apiTokenPattern.test(token);
}

/** Authorization ヘッダーから Bearer の値を取り出す。形式不正なら null */
export function parseBearerToken(header: string | undefined): string | null {
  if (!header) {
    return null;
  }
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  return match ? match[1] : null;
}
