import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";
import {
  API_TOKEN_PREFIX,
  displayPrefix,
  generateApiToken,
  hashApiToken,
  hashEquals,
  parseBearerToken,
} from "../src/lib/apiToken.js";
import { effectivePlan, monthKey } from "../src/lib/plan.js";
import { buildAlarmMessage, parsePushDeliveryMode, toIso8601Seconds } from "../src/lib/push.js";
import { createRateLimiter, createRecentKeys } from "../src/lib/rateLimit.js";
import {
  isAnonymousAppUserId,
  planUpdatesOf,
  PRO_ENTITLEMENT_ID,
  resolveUid,
  type RevenueCatEvent,
} from "../src/lib/revenueCat.js";

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

  it("pro は失効日時を過ぎるまで有効で、失効日時ちょうどは失効済み", () => {
    const now = new Date("2026-09-02T00:00:00Z");
    expect(effectivePlan({ plan: "free" }, now)).toBe("free");
    // free に残った失効日時は pro に昇格させない
    expect(
      effectivePlan({ plan: "free", proExpiresAt: Timestamp.fromMillis(now.getTime() + 1000) }, now),
    ).toBe("free");
    // 失効日時が無い pro は期限なし
    expect(effectivePlan({ plan: "pro" }, now)).toBe("pro");
    expect(effectivePlan({ plan: "pro", proExpiresAt: null }, now)).toBe("pro");
    expect(
      effectivePlan({ plan: "pro", proExpiresAt: Timestamp.fromMillis(now.getTime() + 1) }, now),
    ).toBe("pro");
    expect(
      effectivePlan({ plan: "pro", proExpiresAt: Timestamp.fromMillis(now.getTime()) }, now),
    ).toBe("free");
    expect(
      effectivePlan({ plan: "pro", proExpiresAt: Timestamp.fromMillis(now.getTime() - 1) }, now),
    ).toBe("free");
  });
});

describe("RevenueCat の webhook イベント", () => {
  const NOW = new Date("2026-09-02T00:00:00Z");
  const EXPIRES_AT = new Date(NOW.getTime() + 30 * 24 * 60 * 60 * 1000);
  const ANONYMOUS_APP_USER_ID = "$RCAnonymousID:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6";

  /** 指定しないフィールドは「test-uid の pro entitlement を NOW 時点で通知する」既定値にする */
  function revenueCatEvent(
    overrides: Partial<RevenueCatEvent> & Pick<RevenueCatEvent, "type">,
  ): RevenueCatEvent {
    return {
      id: "event-1",
      event_timestamp_ms: NOW.getTime(),
      app_user_id: "test-uid",
      entitlement_ids: [PRO_ENTITLEMENT_ID],
      ...overrides,
    };
  }

  it("pro の entitlement は失効日時つきで反映し、失効日時を過ぎていれば free にする", () => {
    expect(
      planUpdatesOf(
        revenueCatEvent({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
        NOW,
      ),
    ).toEqual([{ uid: "test-uid", plan: "pro", proExpiresAt: EXPIRES_AT }]);
    // 失効日時が無いイベント (買い切り等) は期限なしの pro
    expect(planUpdatesOf(revenueCatEvent({ type: "RENEWAL" }), NOW)).toEqual([
      { uid: "test-uid", plan: "pro", proExpiresAt: null },
    ]);
    // 失効日時ちょうども失効済みとして free で保存する
    expect(
      planUpdatesOf(
        revenueCatEvent({ type: "EXPIRATION", expiration_at_ms: NOW.getTime() }),
        NOW,
      ),
    ).toEqual([{ uid: "test-uid", plan: "free", proExpiresAt: null }]);
  });

  it("請求猶予期間の終了日時が失効日時より後なら、そちらまで pro にする", () => {
    const graceEndsAt = new Date(EXPIRES_AT.getTime() + 16 * 24 * 60 * 60 * 1000);
    expect(
      planUpdatesOf(
        revenueCatEvent({
          type: "BILLING_ISSUE",
          expiration_at_ms: EXPIRES_AT.getTime(),
          grace_period_expiration_at_ms: graceEndsAt.getTime(),
        }),
        NOW,
      ),
    ).toEqual([{ uid: "test-uid", plan: "pro", proExpiresAt: graceEndsAt }]);
  });

  it("TEST・pro 以外の entitlement・匿名 ID だけのイベントは更新しない", () => {
    expect(planUpdatesOf(revenueCatEvent({ type: "TEST" }), NOW)).toEqual([]);
    expect(
      planUpdatesOf(revenueCatEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["legacy"] }), NOW),
    ).toEqual([]);
    expect(
      planUpdatesOf(revenueCatEvent({ type: "INITIAL_PURCHASE", entitlement_ids: null }), NOW),
    ).toEqual([]);
    expect(
      planUpdatesOf(
        revenueCatEvent({
          type: "INITIAL_PURCHASE",
          app_user_id: ANONYMOUS_APP_USER_ID,
          aliases: [ANONYMOUS_APP_USER_ID],
        }),
        NOW,
      ),
    ).toEqual([]);
  });

  it("TRANSFER は失う側を free、受け取る側を期限なしの pro にし、匿名 ID は除く", () => {
    expect(
      planUpdatesOf(
        revenueCatEvent({
          type: "TRANSFER",
          transferred_from: ["uid-a", ANONYMOUS_APP_USER_ID],
          transferred_to: ["uid-b"],
          expiration_at_ms: EXPIRES_AT.getTime(),
        }),
        NOW,
      ),
    ).toEqual([
      { uid: "uid-a", plan: "free", proExpiresAt: null },
      { uid: "uid-b", plan: "pro", proExpiresAt: null },
    ]);
  });

  it("同じイベントからは何度でも同じ更新を返す (冪等)", () => {
    const purchase = revenueCatEvent({
      type: "INITIAL_PURCHASE",
      expiration_at_ms: EXPIRES_AT.getTime(),
    });
    expect(planUpdatesOf(purchase, NOW)).toEqual(planUpdatesOf(purchase, NOW));
  });

  it("uid は app_user_id を優先し、匿名 ID なら aliases から探す", () => {
    expect(resolveUid({ app_user_id: "test-uid" })).toBe("test-uid");
    expect(resolveUid({ app_user_id: "test-uid", aliases: ["other-uid"] })).toBe("test-uid");
    expect(
      resolveUid({ app_user_id: ANONYMOUS_APP_USER_ID, aliases: [ANONYMOUS_APP_USER_ID, "test-uid"] }),
    ).toBe("test-uid");
    expect(resolveUid({ app_user_id: ANONYMOUS_APP_USER_ID, aliases: [] })).toBeNull();
    expect(resolveUid({ app_user_id: ANONYMOUS_APP_USER_ID, aliases: null })).toBeNull();
    expect(resolveUid({})).toBeNull();
  });

  it("匿名 App User ID は $RCAnonymousID: と英数字 32 文字の形式だけを指す", () => {
    expect(isAnonymousAppUserId(ANONYMOUS_APP_USER_ID)).toBe(true);
    expect(isAnonymousAppUserId("test-uid")).toBe(false);
    // 32 文字に足りない・余る値は匿名 ID として扱わない
    expect(isAnonymousAppUserId("$RCAnonymousID:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d")).toBe(false);
    expect(isAnonymousAppUserId(`${ANONYMOUS_APP_USER_ID}0`)).toBe(false);
    expect(isAnonymousAppUserId("$RCAnonymousID:A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6")).toBe(false);
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
