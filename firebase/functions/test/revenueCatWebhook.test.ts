import type { Server } from "node:http";
import { Timestamp } from "firebase-admin/firestore";
import request from "supertest";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createAppApi } from "../src/api/appApi.js";
import { createExternalApi } from "../src/api/externalApi.js";
import { createRevenueCatWebhook } from "../src/api/revenueCatWebhook.js";
import { APP_CHECK_HEADER } from "../src/lib/appCheck.js";
import { monthKey, planLimits } from "../src/lib/plan.js";
import { PRO_ENTITLEMENT_ID, type RevenueCatEvent } from "../src/lib/revenueCat.js";
import { deletionMarkerRef, userRef } from "../src/lib/store.js";
import { deletedAccountFields } from "../src/schema/index.js";
import {
  clearFirestore,
  createTestContext,
  startTestServer,
  stopTestServer,
  TEST_NOW,
  VALID_APP_CHECK_TOKEN,
  VALID_ID_TOKEN,
  type TestContext,
} from "./helpers.js";

/** RevenueCat Dashboard の webhook 設定に登録する Authorization ヘッダーの値 */
const WEBHOOK_AUTHORIZATION = "Bearer webhook-secret";

/** 30 日のサブスクリプションの失効日時 */
const EXPIRES_AT = new Date(TEST_NOW.getTime() + 30 * 24 * 60 * 60 * 1000);

/** RevenueCat SDK が logIn の前に使う匿名 App User ID (IdentityManager.anonymousRegex と同じ形式) */
const ANONYMOUS_APP_USER_ID = "$RCAnonymousID:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6";

let context: TestContext;
let appApi: Server;
let externalApi: Server;
let webhook: Server;
let eventSequence = 0;

/**
 * webhook のリクエストボディ。
 * 指定しないフィールドは「テスト用のユーザーの pro entitlement を TEST_NOW 時点で通知する」既定値にする
 */
function webhookBody(
  event: Partial<RevenueCatEvent> & Pick<RevenueCatEvent, "type">,
): { api_version: string; event: RevenueCatEvent } {
  eventSequence += 1;
  return {
    api_version: "1.0",
    event: {
      id: `event-${eventSequence}`,
      event_timestamp_ms: TEST_NOW.getTime(),
      app_user_id: context.uid,
      entitlement_ids: [PRO_ENTITLEMENT_ID],
      ...event,
    },
  };
}

function postWebhook(body: object) {
  return request(webhook).post("/").set("authorization", WEBHOOK_AUTHORIZATION).send(body);
}

async function storedUser(uid = context.uid) {
  return userRef(context.deps.firestore, uid).get();
}

/** 無料プランの月間上限に達した状態にする (これ以上の登録は free なら 403、pro なら 201) */
async function fillMonthlyUsage(month: string): Promise<void> {
  await userRef(context.deps.firestore, context.uid).update({
    monthlyUsage: { month, scheduledAlarmCount: planLimits.free.alarmsPerMonth },
  });
}

async function registerDevice(): Promise<void> {
  await request(appApi)
    .post("/v1/devices")
    .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
    .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
    .send({ device_id: "device-1", fcm_token: "fcm-token-1" })
    .expect(200);
}

async function issueApiToken(name = "github-actions"): Promise<{ id: string; token: string }> {
  const response = await request(appApi)
    .post("/v1/api-tokens")
    .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
    .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
    .send({ name })
    .expect(201);
  return { id: response.body.id, token: response.body.token };
}

/** 発火時刻は現在時刻からの相対で指定し、テストが now を動かしても過去にならないようにする */
function scheduleAlarm(token: string) {
  return request(externalApi)
    .post("/v1/alarms")
    .set("authorization", `Bearer ${token}`)
    .send({ fire_in: 300, title: "Deploy finished" });
}

beforeEach(async () => {
  await clearFirestore();
  context = createTestContext();
  appApi = await startTestServer(createAppApi(context.deps));
  externalApi = await startTestServer(createExternalApi(context.deps));
  webhook = await startTestServer(
    createRevenueCatWebhook(context.deps, { authorization: () => WEBHOOK_AUTHORIZATION }),
  );
});

afterEach(async () => {
  await Promise.all([
    stopTestServer(appApi),
    stopTestServer(externalApi),
    stopTestServer(webhook),
  ]);
});

describe("RevenueCat の webhook", () => {
  it("Authorization が無い・一致しないリクエストは 401 で、プランを変えない", async () => {
    await registerDevice();
    const body = webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() });

    const missing = await request(webhook).post("/").send(body).expect(401);
    expect(missing.body.error.code).toBe("unauthenticated");
    // 長さが違う値と、長さが同じで中身が違う値の両方を拒否する
    await request(webhook).post("/").set("authorization", "Bearer wrong").send(body).expect(401);
    await request(webhook)
      .post("/")
      .set("authorization", "Bearer webhook-secreT")
      .send(body)
      .expect(401);

    const user = await storedUser();
    expect(user.get("plan")).toBe("free");
    expect(user.get("planEventAt")).toBeUndefined();
  });

  it("Authorization の設定が空なら、正しいヘッダーでも 401", async () => {
    const unconfigured = await startTestServer(
      createRevenueCatWebhook(context.deps, { authorization: () => "" }),
    );
    try {
      await request(unconfigured)
        .post("/")
        .set("authorization", WEBHOOK_AUTHORIZATION)
        .send(webhookBody({ type: "INITIAL_PURCHASE" }))
        .expect(401);
    } finally {
      await stopTestServer(unconfigured);
    }
  });

  it("ボディの形式が不正なら 400", async () => {
    const noEvent = await postWebhook({ api_version: "1.0" }).expect(400);
    expect(noEvent.body.error.code).toBe("invalid_argument");

    const invalidTimestamp = webhookBody({ type: "INITIAL_PURCHASE" });
    await postWebhook({
      api_version: invalidTimestamp.api_version,
      event: { ...invalidTimestamp.event, event_timestamp_ms: `${TEST_NOW.getTime()}` },
    }).expect(400);
  });

  it("pro の購入を反映し、失効日時と反映したイベントの時刻を保存する", async () => {
    await registerDevice();
    const body = webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() });

    const response = await postWebhook(body).expect(200);

    expect(response.body).toEqual({ event_id: body.event.id, outcomes: ["applied"] });
    const user = await storedUser();
    expect(user.get("plan")).toBe("pro");
    expect((user.get("proExpiresAt") as Timestamp).toMillis()).toBe(EXPIRES_AT.getTime());
    expect((user.get("planEventAt") as Timestamp).toMillis()).toBe(TEST_NOW.getTime());
  });

  it("pro の間は月間の登録数と API トークンの数の上限を外す", async () => {
    await registerDevice();
    const issued = await issueApiToken("first");
    await postWebhook(
      webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
    ).expect(200);
    await fillMonthlyUsage(monthKey(TEST_NOW));

    await scheduleAlarm(issued.token).expect(201);
    // 無料プランなら 1 つまでの API トークンを 2 つ目まで発行できる
    await issueApiToken("second");
  });

  it("失効のイベントで free に戻り、無料プランの上限が戻る", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await postWebhook(
      webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
    ).expect(200);

    const expired = await postWebhook(
      webhookBody({
        type: "EXPIRATION",
        event_timestamp_ms: TEST_NOW.getTime() + 1000,
        expiration_at_ms: TEST_NOW.getTime() - 1000,
      }),
    ).expect(200);

    expect(expired.body.outcomes).toEqual(["applied"]);
    const user = await storedUser();
    expect(user.get("plan")).toBe("free");
    expect(user.get("proExpiresAt")).toBeNull();

    await fillMonthlyUsage(monthKey(TEST_NOW));
    const response = await scheduleAlarm(issued.token).expect(403);
    expect(response.body.error.code).toBe("plan_limit_exceeded");
  });

  it("失効の webhook が届かなくても、失効日時を過ぎたら上限が戻る", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await postWebhook(
      webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
    ).expect(200);

    // 失効日時ちょうどは失効済み (lib/plan.ts の effectivePlan)
    context.setNow(EXPIRES_AT);
    await fillMonthlyUsage(monthKey(EXPIRES_AT));

    const alarm = await scheduleAlarm(issued.token).expect(403);
    expect(alarm.body.error.code).toBe("plan_limit_exceeded");
    const token = await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({ name: "second" })
      .expect(403);
    expect(token.body.error.code).toBe("plan_limit_exceeded");
    // 保存されているプランは webhook が最後に観測した pro のまま (読み取り時に失効日時で判定する)
    expect((await storedUser()).get("plan")).toBe("pro");
  });

  it("保存済みより古いイベントは無視する", async () => {
    await registerDevice();
    await postWebhook(
      webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
    ).expect(200);

    const stale = await postWebhook(
      webhookBody({
        type: "EXPIRATION",
        event_timestamp_ms: TEST_NOW.getTime() - 1000,
        expiration_at_ms: TEST_NOW.getTime() - 2000,
      }),
    ).expect(200);

    expect(stale.body.outcomes).toEqual(["stale"]);
    const user = await storedUser();
    expect(user.get("plan")).toBe("pro");
    expect((user.get("planEventAt") as Timestamp).toMillis()).toBe(TEST_NOW.getTime());
  });

  it("同じイベントの再送で状態が変わらない (冪等)", async () => {
    await registerDevice();
    const body = webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() });

    const first = await postWebhook(body).expect(200);
    const applied = (await storedUser()).data();
    const second = await postWebhook(body).expect(200);

    expect(second.body).toEqual(first.body);
    expect((await storedUser()).data()).toEqual(applied);
  });

  it("TEST イベントは何も更新しない", async () => {
    await registerDevice();
    const before = (await storedUser()).data();

    const response = await postWebhook(webhookBody({ type: "TEST" })).expect(200);

    expect(response.body.outcomes).toEqual([]);
    expect((await storedUser()).data()).toEqual(before);
  });

  it("pro 以外の entitlement のイベントは無視する", async () => {
    await registerDevice();

    const other = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        entitlement_ids: ["legacy"],
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);
    const none = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        entitlement_ids: null,
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);

    expect(other.body.outcomes).toEqual([]);
    expect(none.body.outcomes).toEqual([]);
    expect((await storedUser()).get("plan")).toBe("free");
  });

  it("匿名の App User ID は aliases に uid がある時だけ反映する", async () => {
    await registerDevice();

    const ignored = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        app_user_id: ANONYMOUS_APP_USER_ID,
        aliases: [],
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);
    expect(ignored.body.outcomes).toEqual([]);
    expect((await storedUser()).get("plan")).toBe("free");

    const applied = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        app_user_id: ANONYMOUS_APP_USER_ID,
        aliases: [ANONYMOUS_APP_USER_ID, context.uid],
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);
    expect(applied.body.outcomes).toEqual(["applied"]);
    expect((await storedUser()).get("plan")).toBe("pro");
  });

  it("請求猶予期間があれば、猶予期間の終了日時まで pro のままにする", async () => {
    await registerDevice();
    const graceEndsAt = new Date(EXPIRES_AT.getTime() + 16 * 24 * 60 * 60 * 1000);

    await postWebhook(
      webhookBody({
        type: "BILLING_ISSUE",
        expiration_at_ms: EXPIRES_AT.getTime(),
        grace_period_expiration_at_ms: graceEndsAt.getTime(),
      }),
    ).expect(200);

    const user = await storedUser();
    expect(user.get("plan")).toBe("pro");
    expect((user.get("proExpiresAt") as Timestamp).toMillis()).toBe(graceEndsAt.getTime());
  });

  it("TRANSFER は移行元を free にし、移行先を pro にする", async () => {
    await registerDevice();
    await postWebhook(
      webhookBody({ type: "INITIAL_PURCHASE", expiration_at_ms: EXPIRES_AT.getTime() }),
    ).expect(200);
    // 移行先のユーザーは別の uid の ID トークンで作る (Firestore は同じエミュレータ)
    const receiving = createTestContext("uid-b");
    const receivingAppApi = await startTestServer(createAppApi(receiving.deps));
    try {
      await request(receivingAppApi)
        .post("/v1/devices")
        .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
        .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
        .send({ device_id: "device-b", fcm_token: "fcm-token-b" })
        .expect(200);
    } finally {
      await stopTestServer(receivingAppApi);
    }

    const response = await postWebhook(
      webhookBody({
        type: "TRANSFER",
        transferred_from: [context.uid],
        transferred_to: [receiving.uid],
      }),
    ).expect(200);

    expect(response.body.outcomes).toEqual(["applied", "applied"]);
    const losing = await storedUser();
    expect(losing.get("plan")).toBe("free");
    expect(losing.get("proExpiresAt")).toBeNull();
    // TRANSFER には失効日時が載らないため、受け取る側は期限なしで登録して後続のイベントを待つ
    const receivingUser = await storedUser(receiving.uid);
    expect(receivingUser.get("plan")).toBe("pro");
    expect(receivingUser.get("proExpiresAt")).toBeNull();
  });

  it("未登録の uid でも pro なら作成し、free なら作らない", async () => {
    const created = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        app_user_id: "unregistered-pro",
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);

    expect(created.body.outcomes).toEqual(["applied"]);
    const user = await storedUser("unregistered-pro");
    expect(user.get("plan")).toBe("pro");
    expect(user.get("monthlyUsage")).toEqual({
      month: monthKey(TEST_NOW),
      scheduledAlarmCount: 0,
    });

    const ignored = await postWebhook(
      webhookBody({
        type: "EXPIRATION",
        app_user_id: "unregistered-free",
        expiration_at_ms: TEST_NOW.getTime() - 1000,
      }),
    ).expect(200);

    expect(ignored.body.outcomes).toEqual(["unknown_user"]);
    expect((await storedUser("unregistered-free")).exists).toBe(false);
  });

  it("Firebase Auth にユーザーが無い uid のドキュメントは作らない (削除済みアカウントの復活を防ぐ)", async () => {
    context.setAuthUserExists(false);

    const response = await postWebhook(
      webhookBody({
        type: "RENEWAL",
        app_user_id: "deleted-uid",
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);

    expect(response.body.outcomes).toEqual(["auth_user_missing"]);
    expect((await storedUser("deleted-uid")).exists).toBe(false);
  });

  it("削除処理中のアカウントには書き込まない", async () => {
    await deletionMarkerRef(context.deps.firestore, "deleting-uid").set({
      [deletedAccountFields.requestedAt]: Timestamp.fromDate(TEST_NOW),
    });

    const response = await postWebhook(
      webhookBody({
        type: "INITIAL_PURCHASE",
        app_user_id: "deleting-uid",
        expiration_at_ms: EXPIRES_AT.getTime(),
      }),
    ).expect(200);

    expect(response.body.outcomes).toEqual(["account_deleted"]);
    expect((await storedUser("deleting-uid")).exists).toBe(false);
  });
});
