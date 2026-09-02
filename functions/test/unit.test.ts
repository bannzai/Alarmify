import { describe, expect, it } from "vitest";
import {
  API_TOKEN_PREFIX,
  displayPrefix,
  generateApiToken,
  hashApiToken,
  hashEquals,
  parseBearerToken,
} from "../src/lib/apiToken.js";
import { monthKey } from "../src/lib/plan.js";
import { buildAlarmMessage, parsePushDeliveryMode, toIso8601Seconds } from "../src/lib/push.js";
import { createRateLimiter, createRecentKeys } from "../src/lib/rateLimit.js";

describe("API トークン", () => {
  it("平文は接頭辞つきで、毎回異なる", () => {
    const first = generateApiToken();
    const second = generateApiToken();
    expect(first.token.startsWith(API_TOKEN_PREFIX)).toBe(true);
    expect(first.token).not.toBe(second.token);
  });

  it("保存するのは SHA-256 のハッシュと表示用プレフィックスだけ", () => {
    const generated = generateApiToken();
    expect(generated.hash).toBe(hashApiToken(generated.token));
    expect(generated.hash).toHaveLength(64);
    expect(generated.hash).not.toContain(generated.token);
    expect(generated.prefix).toBe(displayPrefix(generated.token));
    expect(generated.prefix.length).toBeLessThan(generated.token.length);
  });

  it("ハッシュの比較は長さ違いでも例外にならない", () => {
    expect(hashEquals("abc", "abc")).toBe(true);
    expect(hashEquals("abc", "abcd")).toBe(false);
    expect(hashEquals("abc", "abd")).toBe(false);
  });

  it("Authorization ヘッダーから Bearer を取り出す", () => {
    expect(parseBearerToken("Bearer alm_xyz")).toBe("alm_xyz");
    expect(parseBearerToken("bearer alm_xyz")).toBe("alm_xyz");
    expect(parseBearerToken("Basic alm_xyz")).toBeNull();
    expect(parseBearerToken(undefined)).toBeNull();
  });
});

describe("プラン", () => {
  it("月間上限のキーは UTC の YYYY-MM", () => {
    expect(monthKey(new Date("2026-09-02T00:00:00Z"))).toBe("2026-09");
    expect(monthKey(new Date("2026-12-31T23:59:59Z"))).toBe("2026-12");
    // JST では翌月でも UTC では 8 月
    expect(monthKey(new Date("2026-09-01T00:00:00+09:00"))).toBe("2026-08");
  });
});

describe("push payload", () => {
  const fireAt = new Date("2026-09-03T07:00:00.123Z");

  it("fire_at は小数秒を含まない ISO 8601 にする (iOS の ISO8601DateFormatter が既定で解釈できる形式)", () => {
    expect(toIso8601Seconds(fireAt)).toBe("2026-09-03T07:00:00Z");
  });

  it("notification-service では mutable-content の visible push を作る", () => {
    const message = buildAlarmMessage({
      fcmToken: "fcm-token",
      id: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E",
      action: "schedule",
      fireAt,
      title: "Deploy finished",
      mode: "notification-service",
    });
    expect(message.apns?.headers?.["apns-push-type"]).toBe("alert");
    expect(message.apns?.payload?.aps.mutableContent).toBe(true);
    expect(message.apns?.payload?.aps.contentAvailable).toBeUndefined();
    expect(message.apns?.payload?.alarm).toEqual({
      id: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E",
      action: "schedule",
      fire_at: "2026-09-03T07:00:00Z",
      title: "Deploy finished",
    });
  });

  it("background では content-available の silent push を作る", () => {
    const message = buildAlarmMessage({
      fcmToken: "fcm-token",
      id: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E",
      action: "cancel",
      fireAt: null,
      title: null,
      mode: "background",
    });
    expect(message.apns?.headers?.["apns-push-type"]).toBe("background");
    expect(message.apns?.payload?.aps.contentAvailable).toBe(true);
    expect(message.apns?.payload?.aps.alert).toBeUndefined();
    // cancel は id と action だけで足りる (AlarmRequest.swift)
    expect(message.apns?.payload?.alarm).toEqual({
      id: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E",
      action: "cancel",
    });
  });

  it("配送経路は環境変数で切り替え、未知の値は既定に落とす", () => {
    expect(parsePushDeliveryMode("background")).toBe("background");
    expect(parsePushDeliveryMode("notification-service")).toBe("notification-service");
    expect(parsePushDeliveryMode(undefined)).toBe("notification-service");
    expect(parsePushDeliveryMode("unknown")).toBe("notification-service");
  });
});

describe("レート制限", () => {
  it("ウィンドウ内は上限まで通し、超えたら拒否する", () => {
    let now = new Date("2026-09-02T00:00:00Z");
    const limiter = createRateLimiter({ limit: 2, windowMs: 1000, now: () => now });
    expect(limiter.consume("a")).toBe(true);
    expect(limiter.consume("a")).toBe(true);
    expect(limiter.consume("a")).toBe(false);
    // キーが違えば独立して数える
    expect(limiter.consume("b")).toBe(true);
    // ウィンドウが変われば数え直す
    now = new Date(now.getTime() + 1000);
    expect(limiter.consume("a")).toBe(true);
  });

  it("保持するキーは上限を超えない", () => {
    const now = new Date("2026-09-02T00:00:00Z");
    const limiter = createRateLimiter({ limit: 1, windowMs: 60_000, now: () => now, maxKeys: 2 });
    for (let index = 0; index < 10; index += 1) {
      expect(limiter.consume(`key-${index}`)).toBe(true);
    }
    // 追い出された古いキーは数え直しになるが、上限を超えたキーは拒否され続ける
    expect(limiter.consume("key-9")).toBe(false);
  });
});

describe("直近に見たキー", () => {
  it("期限が切れたら忘れる", () => {
    let now = new Date("2026-09-02T00:00:00Z");
    const known = createRecentKeys({ now: () => now, ttlMs: 1000, maxKeys: 10 });
    known.add("token");
    expect(known.has("token")).toBe(true);
    now = new Date(now.getTime() + 1000);
    expect(known.has("token")).toBe(false);
  });

  it("件数の上限を超えたら古いものから忘れる", () => {
    const now = new Date("2026-09-02T00:00:00Z");
    const known = createRecentKeys({ now: () => now, ttlMs: 60_000, maxKeys: 2 });
    known.add("first");
    known.add("second");
    known.add("third");
    expect(known.has("first")).toBe(false);
    expect(known.has("third")).toBe(true);
  });
});
