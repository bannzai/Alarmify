/**
 * 固定ウィンドウのレート制限。
 * 外部サービス向け API は誰でも叩けるため、認証前の Firestore 読み取りが際限なく走らないようにする
 * (ADR 0001 の「API トークン + レート制限で守る」の一次防御。インスタンス単位のため厳密な総量制限ではない)
 */
export interface RateLimit {
  limit: number;
  windowMs: number;
}

export interface RateLimiterOptions extends RateLimit {
  now: () => Date;
  /** 保持するキーの上限。Function インスタンスのメモリを使い切らないための頭打ち */
  maxKeys?: number;
}

export interface RateLimiter {
  /** 呼び出しを 1 回消費する。上限を超えていたら false */
  consume(key: string): boolean;
}

interface Window {
  startedAt: number;
  count: number;
}

/** 期限切れのウィンドウを捨て、それでも空かなければ古い順に捨てる */
function makeRoom(windows: Map<string, Window>, timestamp: number, windowMs: number, maxKeys: number): void {
  for (const [key, window] of windows) {
    if (timestamp - window.startedAt >= windowMs) {
      windows.delete(key);
    }
  }
  while (windows.size >= maxKeys) {
    let oldestKey: string | null = null;
    let oldestStartedAt = Number.POSITIVE_INFINITY;
    for (const [key, window] of windows) {
      if (window.startedAt < oldestStartedAt) {
        oldestStartedAt = window.startedAt;
        oldestKey = key;
      }
    }
    if (oldestKey === null) {
      return;
    }
    windows.delete(oldestKey);
  }
}

export function createRateLimiter({
  limit,
  windowMs,
  now,
  maxKeys = 10_000,
}: RateLimiterOptions): RateLimiter {
  const windows = new Map<string, Window>();

  return {
    consume(key) {
      const timestamp = now().getTime();
      const window = windows.get(key);
      if (window && timestamp - window.startedAt < windowMs) {
        window.count += 1;
        return window.count <= limit;
      }
      if (!window && windows.size >= maxKeys) {
        makeRoom(windows, timestamp, windowMs, maxKeys);
      }
      windows.set(key, { startedAt: timestamp, count: 1 });
      return true;
    },
  };
}

export interface RecentKeys {
  has(key: string): boolean;
  add(key: string): void;
}

/**
 * 直近に見たキーを覚えておく、期限と件数の上限つきの集合。
 * 実在すると分かっているキーを、まだ実在が分からないキーと同じ枠で数えないために使う
 */
export function createRecentKeys(options: {
  now: () => Date;
  ttlMs: number;
  maxKeys: number;
}): RecentKeys {
  const seen = new Map<string, number>();

  return {
    has(key) {
      const seenAt = seen.get(key);
      if (seenAt === undefined) {
        return false;
      }
      if (options.now().getTime() - seenAt >= options.ttlMs) {
        seen.delete(key);
        return false;
      }
      return true;
    },
    add(key) {
      const timestamp = options.now().getTime();
      if (!seen.has(key) && seen.size >= options.maxKeys) {
        for (const [existingKey, seenAt] of seen) {
          if (timestamp - seenAt >= options.ttlMs) {
            seen.delete(existingKey);
          }
        }
        while (seen.size >= options.maxKeys) {
          const oldest = seen.keys().next();
          if (oldest.done) {
            break;
          }
          seen.delete(oldest.value);
        }
      }
      seen.delete(key);
      seen.set(key, timestamp);
    },
  };
}
