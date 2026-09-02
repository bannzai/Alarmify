/**
 * 固定ウィンドウのレート制限。
 * 外部サービス向け API は誰でも叩けるため、認証前の Firestore 読み取りが際限なく走らないようにする
 * (ADR 0001 の「API トークン + レート制限で守る」の一次防御。インスタンス単位のため厳密な総量制限ではない)
 */
export interface RateLimiterOptions {
  limit: number;
  windowMs: number;
  now: () => Date;
  /** 保持するキーの上限。超えたら期限切れのキーを掃除する */
  maxKeys?: number;
}

export interface RateLimiter {
  /** 呼び出しを 1 回消費する。上限を超えていたら false */
  consume(key: string): boolean;
}

export function createRateLimiter({
  limit,
  windowMs,
  now,
  maxKeys = 10_000,
}: RateLimiterOptions): RateLimiter {
  const windows = new Map<string, { startedAt: number; count: number }>();

  return {
    consume(key) {
      const timestamp = now().getTime();
      if (windows.size >= maxKeys) {
        for (const [existingKey, window] of windows) {
          if (timestamp - window.startedAt >= windowMs) {
            windows.delete(existingKey);
          }
        }
      }
      const window = windows.get(key);
      if (!window || timestamp - window.startedAt >= windowMs) {
        windows.set(key, { startedAt: timestamp, count: 1 });
        return true;
      }
      window.count += 1;
      return window.count <= limit;
    },
  };
}
