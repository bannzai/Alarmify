import type { Server } from "node:http";
import { Timestamp } from "firebase-admin/firestore";
import type { TokenMessage } from "firebase-admin/messaging";
import request from "supertest";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createAppApi } from "../src/api/appApi.js";
import { createExternalApi } from "../src/api/externalApi.js";
import { APP_CHECK_HEADER } from "../src/lib/appCheck.js";
import { toIso8601Seconds } from "../src/lib/push.js";
import { MAX_DEVICES_PER_USER } from "../src/lib/store.js";
import { MAX_FIRE_AT_AHEAD_DAYS, MIN_FIRE_AT_LEAD_SECONDS } from "../src/api/externalApi.js";
import { userRef } from "../src/lib/store.js";
import { collections, deletedAccountFields } from "../src/schema/index.js";
import {
  ANONYMOUS_ID_TOKEN,
  ANONYMOUS_UID,
  clearFirestore,
  createTestContext,
  startTestServer,
  stopTestServer,
  TEST_NOW,
  VALID_APP_CHECK_TOKEN,
  VALID_ID_TOKEN,
  type TestContext,
} from "./helpers.js";

const FIRE_AT = new Date("2026-09-03T07:00:00Z");

let context: TestContext;
let appApi: Server;
let externalApi: Server;

async function registerDevice(deviceId = "device-1", fcmToken = "fcm-token-1"): Promise<void> {
  await request(appApi)
    .post("/v1/devices")
    .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
    .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
    .send({ device_id: deviceId, fcm_token: fcmToken })
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

beforeEach(async () => {
  await clearFirestore();
  context = createTestContext();
  appApi = await startTestServer(createAppApi(context.deps));
  externalApi = await startTestServer(createExternalApi(context.deps));
});

afterEach(async () => {
  await Promise.all([stopTestServer(appApi), stopTestServer(externalApi)]);
});

describe("アプリ向け API", () => {
  it("ID トークンが無ければ 401", async () => {
    const response = await request(appApi)
      .post("/v1/api-tokens")
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({})
      .expect(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("ID トークンが不正なら 401", async () => {
    await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", "Bearer invalid")
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({})
      .expect(401);
  });

  it("App Check トークンが無ければ 401 (ID トークンが有効でも通さない)", async () => {
    const response = await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .send({})
      .expect(401);
    expect(response.body.error.code).toBe("app_check_required");
  });

  it("App Check トークンが不正なら 401", async () => {
    const response = await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, "invalid-app-check-token")
      .send({})
      .expect(401);
    expect(response.body.error.code).toBe("app_check_invalid");
  });

  it("monitor では App Check トークンが無くても通る (強制適用の前段)", async () => {
    context.setAppCheckEnforcementMode("monitor");
    await request(appApi)
      .post("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .send({ device_id: "device-1", fcm_token: "fcm-token-1" })
      .expect(200);
  });

  it("monitor では不正な App Check トークンも通る (記録するだけで拒否しない)", async () => {
    context.setAppCheckEnforcementMode("monitor");
    await request(appApi)
      .post("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, "invalid-app-check-token")
      .send({ device_id: "device-1", fcm_token: "fcm-token-1" })
      .expect(200);
  });

  it("外部サービス向け API は App Check を要求しない (API トークンで守る)", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);
  });

  it("同じ device_id への再登録は上書きになる (冪等)", async () => {
    await registerDevice("device-1", "fcm-token-1");
    await registerDevice("device-1", "fcm-token-2");
    const snapshot = await userRef(context.deps.firestore, context.uid)
      .collection(collections.devices)
      .get();
    expect(snapshot.size).toBe(1);
    expect(snapshot.docs[0].get("fcmToken")).toBe("fcm-token-2");
    expect((snapshot.docs[0].get("createdAt") as Timestamp).toMillis()).toBe(TEST_NOW.getTime());
  });

  it("登録できる端末数には上限があり、既存端末の更新は上限に関係なく通る", async () => {
    for (let index = 0; index < MAX_DEVICES_PER_USER; index += 1) {
      await registerDevice(`device-${index}`, `fcm-token-${index}`);
    }
    const response = await request(appApi)
      .post("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({ device_id: "device-over", fcm_token: "fcm-token-over" })
      .expect(403);
    expect(response.body.error.code).toBe("device_limit_exceeded");
    await registerDevice("device-0", "fcm-token-updated");
  });

  it('device_id に "/" を含む登録は 400', async () => {
    await request(appApi)
      .post("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({ device_id: "a/b/c", fcm_token: "fcm-token" })
      .expect(400);
  });

  it("登録済みの端末を一覧できる", async () => {
    await registerDevice("device-1", "fcm-token-1");
    await registerDevice("device-2", "fcm-token-2");
    const response = await request(appApi)
      .get("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(response.body.devices.map((device: { device_id: string }) => device.device_id)).toEqual([
      "device-1",
      "device-2",
    ]);
  });

  it("平文のトークンは保存せず、ハッシュとプレフィックスだけを持つ", async () => {
    const issued = await issueApiToken();
    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.apiTokens)
      .doc(issued.id)
      .get();
    expect(stored.get("hash")).toHaveLength(64);
    expect(stored.get("prefix")).toBe(issued.token.slice(0, 12));
    expect(JSON.stringify(stored.data())).not.toContain(issued.token);
  });

  it("無料プランでは API トークンを 1 つまでしか発行できない", async () => {
    await issueApiToken("first");
    const response = await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({ name: "second" })
      .expect(403);
    expect(response.body.error.code).toBe("plan_limit_exceeded");
  });

  it("失効させたトークンは一覧から消え、再度発行できる", async () => {
    const issued = await issueApiToken();
    await request(appApi)
      .delete(`/v1/api-tokens/${issued.id}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(204);
    const list = await request(appApi)
      .get("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(list.body.api_tokens).toHaveLength(0);
    expect(list.body.next_cursor).toBeNull();
    await issueApiToken("second");
  });
});

describe("外部サービス向け API", () => {
  it("API トークン発行 → POST /v1/alarms → FCM 送信関数が呼ばれる", async () => {
    await registerDevice();
    const issued = await issueApiToken();

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);

    expect(response.body.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(response.body.status).toBe("scheduled");
    expect(response.body.delivery).toEqual({ success_count: 1, failure_count: 0 });

    expect(context.sentBatches).toHaveLength(1);
    const [messages] = context.sentBatches;
    expect(messages).toHaveLength(1);
    expect((messages[0] as TokenMessage).token).toBe("fcm-token-1");
    expect(messages[0].apns?.payload?.alarm).toEqual({
      id: response.body.id,
      action: "schedule",
      fire_at: "2026-09-03T07:00:00Z",
      title: "Deploy finished",
    });

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(response.body.id)
      .get();
    expect(stored.get("status")).toBe("scheduled");
    expect(stored.get("tokenId")).toBe(issued.id);
    expect(stored.get("delivery").successCount).toBe(1);
    // 保持期間 30 日は発火時刻を基準に取る (発火まで取り消せる必要があるため)
    expect((stored.get("expiresAt") as Timestamp).toMillis()).toBe(
      FIRE_AT.getTime() + 30 * 24 * 60 * 60 * 1000,
    );
  });

  it("送信に失敗した数もアラームに記録する", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    context.failNextPush();
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 0, failure_count: 1 });
    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(response.body.id)
      .get();
    expect(stored.get("delivery").errors).toEqual(["messaging/invalid-registration-token"]);
  });

  it("無効な API トークンは 401", async () => {
    await registerDevice();
    await issueApiToken();
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", "Bearer alm_unknown")
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(401);
    expect(context.sentBatches).toHaveLength(0);
  });

  it("失効済みの API トークンは 401", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await request(appApi)
      .delete(`/v1/api-tokens/${issued.id}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(204);
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(401);
  });

  it("fire_in は受信からの秒数で発火時刻を決め、リードタイム未満は最小値へ繰り上げる", async () => {
    await registerDevice();
    const issued = await issueApiToken();

    const later = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: 300, title: "Backup finished" })
      .expect(201);
    expect(later.body.fire_at).toBe(new Date(TEST_NOW.getTime() + 300 * 1000).toISOString());

    const asap = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: 0 })
      .expect(201);
    expect(asap.body.fire_at).toBe(
      new Date(TEST_NOW.getTime() + MIN_FIRE_AT_LEAD_SECONDS * 1000).toISOString(),
    );

    // 受信時刻に秒未満があっても、秒単位への丸めでリードタイムを割り込まない (切り上げ)
    context.setNow(new Date(TEST_NOW.getTime() + 500));
    const subSecond = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: 0 })
      .expect(201);
    expect(subSecond.body.fire_at).toBe(
      new Date(TEST_NOW.getTime() + (MIN_FIRE_AT_LEAD_SECONDS + 1) * 1000).toISOString(),
    );

    // 上限ちょうど (365 日) も、秒への切り上げで境界をはみ出した分を理由に弾かない
    const maxDelay = MAX_FIRE_AT_AHEAD_DAYS * 24 * 60 * 60;
    const atMax = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: maxDelay })
      .expect(201);
    expect(atMax.body.fire_at).toBe(
      new Date(TEST_NOW.getTime() + 1000 + maxDelay * 1000).toISOString(),
    );
  });

  it("fire_at と fire_in は両方指定・両方省略とも 400", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const both = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), fire_in: 60 })
      .expect(400);
    expect(both.body.error.code).toBe("invalid_argument");
    const neither = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ title: "no time" })
      .expect(400);
    expect(neither.body.error.code).toBe("invalid_argument");
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: -1 })
      .expect(400);
    // Date の範囲を超える値は 500 ではなく 400
    const huge = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_in: 9_000_000_000_000 })
      .expect(400);
    expect(huge.body.error.code).toBe("invalid_argument");
  });

  it("fire_at が過去・形式不正なら 400", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const past = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: "2026-09-01T00:00:00Z" })
      .expect(400);
    expect(past.body.error.code).toBe("invalid_argument");
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: "2026/09/03 07:00" })
      .expect(400);
  });

  it("端末が未登録なら 409", async () => {
    const issued = await issueApiToken();
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(409);
    expect(response.body.error.code).toBe("no_device_registered");
  });

  it("無料プランの月 50 件を超えると 403", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      monthlyUsage: { month: "2026-09", scheduledAlarmCount: 50 },
    });
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(403);
    expect(response.body.error.code).toBe("plan_limit_exceeded");
  });

  it.each([
    ["free", 50],
    ["pro", 1000],
  ] as const)("%s は月 %i 件目まで登録でき再送は加算せず次の登録を拒否する", async (plan, limit) => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      plan,
      monthlyUsage: { month: "2026-09", scheduledAlarmCount: limit - 1 },
    });
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: created.body.id, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(200);
    const rejected = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(403);
    expect(rejected.body.error.code).toBe("plan_limit_exceeded");
    expect((await userRef(context.deps.firestore, context.uid).get()).get("monthlyUsage.scheduledAlarmCount"))
      .toBe(limit);
  });

  it("月が変わると月間の登録数を数え直す", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      monthlyUsage: { month: "2026-08", scheduledAlarmCount: 50 },
    });
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    const user = await userRef(context.deps.firestore, context.uid).get();
    expect(user.get("monthlyUsage")).toEqual({ month: "2026-09", scheduledAlarmCount: 1 });
  });

  it("DELETE /v1/alarms/{id} は取り消しの push を送り、繰り返しても同じ結果になる (冪等)", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const response = await request(externalApi)
        .delete(`/v1/alarms/${created.body.id}`)
        .set("authorization", `Bearer ${issued.token}`)
        .expect(200);
      expect(response.body.status).toBe("canceled");
    }
    const cancelMessages = context.sentBatches.slice(1);
    expect(cancelMessages).toHaveLength(2);
    for (const messages of cancelMessages) {
      expect(messages[0].apns?.payload?.alarm).toEqual({
        id: created.body.id,
        action: "cancel",
        title: "Deploy finished",
      });
    }
  });

  it("保持期間より先の fire_at でも、発火まではアラームの記録が残る", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const farFuture = new Date(TEST_NOW.getTime() + 90 * 24 * 60 * 60 * 1000);
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(farFuture) })
      .expect(201);
    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(created.body.id)
      .get();
    expect((stored.get("expiresAt") as Timestamp).toMillis()).toBe(
      farFuture.getTime() + 30 * 24 * 60 * 60 * 1000,
    );
  });

  it("暦日として存在しない fire_at は 400 (Date.parse の丸めを受け入れない)", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: "2027-02-29T07:00:00Z" })
      .expect(400);
    expect(response.body.error.code).toBe("invalid_argument");
  });

  it("形式が違うトークンは Firestore を引かずに 401", async () => {
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", "Bearer alm_short")
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(401);
  });

  it("実在しないトークンの流量は呼び出し元によらずインスタンス単位で頭打ちにする", async () => {
    // X-Forwarded-For を詐称しても回避できないことを、呼び出しごとに別の値を送って確かめる
    const limited = await startTestServer(
      createExternalApi(context.deps, { globalRateLimit: { limit: 2, windowMs: 60_000 } }),
    );
    try {
      const token = `alm_${"a".repeat(43)}`;
      for (let count = 0; count < 2; count += 1) {
        await request(limited)
          .post("/v1/alarms")
          .set("authorization", `Bearer ${token}`)
          .set("x-forwarded-for", `203.0.113.${count}`)
          .send({})
          .expect(401);
      }
      const response = await request(limited)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${token}`)
        .set("x-forwarded-for", "203.0.113.99")
        .send({})
        .expect(429);
      expect(response.body.error.code).toBe("rate_limited");
    } finally {
      await stopTestServer(limited);
    }
  });

  it("実在しないトークンの大量送信で、実在するトークンの呼び出しが止まらない", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const limited = await startTestServer(
      createExternalApi(context.deps, { globalRateLimit: { limit: 1, windowMs: 60_000 } }),
    );
    try {
      // 先に 1 度通して、実在するトークンだと分かっている状態にする
      await request(limited)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT) })
        .expect(201);
      // 実在しないトークンで共有の枠を使い切る
      for (let count = 0; count < 2; count += 1) {
        await request(limited)
          .post("/v1/alarms")
          .set("authorization", `Bearer alm_${"b".repeat(43)}`)
          .send({});
      }
      await request(limited)
        .delete("/v1/alarms/00000000-0000-4000-8000-000000000000")
        .set("authorization", `Bearer ${issued.token}`)
        .expect(404);
    } finally {
      await stopTestServer(limited);
    }
  });

  it("認証後の上限は API トークン単位で数える", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const limited = await startTestServer(
      createExternalApi(context.deps, { tokenRateLimit: { limit: 1, windowMs: 60_000 } }),
    );
    try {
      await request(limited)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT) })
        .expect(201);
      await request(limited)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT) })
        .expect(429);
    } finally {
      await stopTestServer(limited);
    }
  });

  it("同じ id での再送は二重登録せず、push だけ送り直す", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const alarmId = "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e";
    const body = { id: alarmId, fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" };

    const first = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send(body)
      .expect(201);
    const second = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send(body)
      .expect(200);
    expect(second.body.id).toBe(first.body.id);
    expect(second.body.fire_at).toBe(first.body.fire_at);

    const alarms = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(alarms.docs.map((doc) => doc.id)).toEqual([alarmId]);
    // 月間上限は 1 回しか消費しない
    const user = await userRef(context.deps.firestore, context.uid).get();
    expect(user.get("monthlyUsage")).toEqual({ month: "2026-09", scheduledAlarmCount: 1 });
    // 配送だけが失敗した場合に再試行できるよう、push は毎回送る
    expect(context.sentBatches).toHaveLength(2);
  });

  it("同じ id に別の fire_at を送ると再スケジュールになる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const alarmId = "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e";
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT), title: "first" })
      .expect(201);

    const rescheduled = new Date(FIRE_AT.getTime() + 60 * 60 * 1000);
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(rescheduled), title: "second" })
      .expect(200);
    expect(response.body.fire_at).toBe(rescheduled.toISOString());
    expect(response.body.title).toBe("second");
    // 内容が変わる再スケジュールは新しい登録として月間上限を消費する
    const user = await userRef(context.deps.firestore, context.uid).get();
    expect(user.get("monthlyUsage")).toEqual({ month: "2026-09", scheduledAlarmCount: 2 });
    expect(context.sentBatches.at(-1)?.[0].apns?.payload?.alarm).toEqual({
      id: alarmId,
      action: "schedule",
      fire_at: toIso8601Seconds(rescheduled),
      title: "second",
    });
  });

  it("取り消したアラームは同じ id への POST で登録し直せる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const alarmId = "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e";
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    await request(externalApi)
      .delete(`/v1/alarms/${alarmId}`)
      .set("authorization", `Bearer ${issued.token}`)
      .expect(200);

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(200);
    expect(response.body.status).toBe("scheduled");
  });

  it("取り消したアラームの保持期限は取り消し時点から数え直す", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const farFuture = new Date(TEST_NOW.getTime() + 365 * 24 * 60 * 60 * 1000);
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(farFuture) })
      .expect(201);
    await request(externalApi)
      .delete(`/v1/alarms/${created.body.id}`)
      .set("authorization", `Bearer ${issued.token}`)
      .expect(200);

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(created.body.id)
      .get();
    expect((stored.get("expiresAt") as Timestamp).toMillis()).toBe(
      TEST_NOW.getTime() + 30 * 24 * 60 * 60 * 1000,
    );
  });

  it("push の送信に失敗しても登録は成立し、id と失敗の記録を返す", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    context.throwNextPush();
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 0, failure_count: 1 });

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(response.body.id)
      .get();
    expect(stored.get("delivery").errors).toEqual(["fcm unavailable"]);
  });

  it("取り消しの配送結果もアラームに記録する", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    context.failNextPush();
    await request(externalApi)
      .delete(`/v1/alarms/${created.body.id}`)
      .set("authorization", `Bearer ${issued.token}`)
      .expect(200);

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(created.body.id)
      .get();
    expect(stored.get("delivery").errors).toEqual(["messaging/invalid-registration-token"]);
  });

  it("大文字小文字が違う同じ UUID は 1 件として扱う", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const alarmId = "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E";
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    const second = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId.toLowerCase(), fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(200);
    expect(second.body.id).toBe(alarmId.toLowerCase());

    const alarms = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(alarms.size).toBe(1);
  });

  it("fire_at が先すぎると 400", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const tooFar = new Date(TEST_NOW.getTime() + (MAX_FIRE_AT_AHEAD_DAYS + 1) * 24 * 60 * 60 * 1000);
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(tooFar) })
      .expect(400);
    expect(response.body.error.code).toBe("invalid_argument");
  });

  it("再スケジュールした時は、そのトークンを履歴の出どころにする", async () => {
    await registerDevice();
    const first = await issueApiToken("first");
    const alarmId = "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e";
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${first.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);

    // 1 つ目を失効させて 2 つ目を発行する (無料プランは同時に 1 つまで)
    await request(appApi)
      .delete(`/v1/api-tokens/${first.id}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(204);
    const second = await issueApiToken("second");

    // 内容が同じでもトークンが違えば、そのトークンの登録として出どころと上限を付け替える
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${second.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(200);

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(alarmId)
      .get();
    expect(stored.get("tokenId")).toBe(second.id);
    const user = await userRef(context.deps.firestore, context.uid).get();
    expect(user.get("monthlyUsage").scheduledAlarmCount).toBe(2);
  });

  it("大文字の UUID で取り消しても同じアラームに届く", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const alarmId = "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E";
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: alarmId, fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    const response = await request(externalApi)
      .delete(`/v1/alarms/${alarmId}`)
      .set("authorization", `Bearer ${issued.token}`)
      .expect(200);
    expect(response.body.id).toBe(alarmId.toLowerCase());
    await request(externalApi)
      .delete("/v1/alarms/not-a-uuid")
      .set("authorization", `Bearer ${issued.token}`)
      .expect(400);
  });

  it("fire_at は小数秒を切り捨て、配送に要する余裕より近い日時は 400", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    context.setNow(new Date("2026-09-02T12:00:00.800Z"));
    // 切り捨てると 12:00:30 で、リードタイム (30 秒) にわずかに足りない
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: "2026-09-02T12:00:30.900Z" })
      .expect(400);
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: `2026-09-02T12:00:${MIN_FIRE_AT_LEAD_SECONDS + 1}.900Z` })
      .expect(201);
    expect(response.body.fire_at).toBe(`2026-09-02T12:00:${MIN_FIRE_AT_LEAD_SECONDS + 1}.000Z`);
  });

  it("id が UUID でなければ 400", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ id: "not-a-uuid", fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(400);
  });

  it("ボディが上限を超えたら 413", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .set("content-type", "application/json")
      .send(JSON.stringify({ fire_at: toIso8601Seconds(FIRE_AT), title: "a".repeat(40 * 1024) }))
      .expect(413);
    expect(response.body.error.code).toBe("payload_too_large");
  });

  it("存在しないアラームの取り消しは 404", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await request(externalApi)
      .delete("/v1/alarms/00000000-0000-4000-8000-000000000000")
      .set("authorization", `Bearer ${issued.token}`)
      .expect(404);
  });
});

describe("プラン別の配送先端末", () => {
  /**
   * 2 台を登録順が分かる形で用意する。
   * createdAt は deps.now() で決まるため、時刻を進めて同着にせず、
   * device_id の辞書順と登録順が逆になる名前にして「登録順で選んでいるか」を確かめられるようにする
   */
  async function registerTwoDevices(): Promise<void> {
    await registerDevice("device-b", "fcm-token-first");
    context.setNow(new Date(TEST_NOW.getTime() + 1000));
    await registerDevice("device-a", "fcm-token-second");
    context.setNow(TEST_NOW);
  }

  /** batchIndex 回目の送信が、どの端末の FCM トークンへ宛てられたかを送った順に返す */
  function sentTokens(batchIndex: number): string[] {
    return context.sentBatches[batchIndex].map((message) => (message as TokenMessage).token);
  }

  it("無料プランは 2 台登録していても最初に登録した 1 台だけへ配送する", async () => {
    await registerTwoDevices();
    const issued = await issueApiToken();

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 1, failure_count: 0 });
    expect(sentTokens(0)).toEqual(["fcm-token-first"]);

    // 2 台目以降の端末登録自体は受け付けたまま (登録は拒否せず配送先だけを絞る)
    const devices = await request(appApi)
      .get("/v1/devices")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(devices.body.devices.map((device: { device_id: string }) => device.device_id)).toEqual([
      "device-b",
      "device-a",
    ]);
  });

  it("pro プランは登録済みの全端末へ配送する", async () => {
    await registerTwoDevices();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 2, failure_count: 0 });
    expect(sentTokens(0)).toEqual(["fcm-token-first", "fcm-token-second"]);
  });

  it("pro の失効日時を過ぎていれば、plan が pro のままでも最初の 1 台だけへ配送する", async () => {
    await registerTwoDevices();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      plan: "pro",
      proExpiresAt: Timestamp.fromMillis(TEST_NOW.getTime() - 1),
    });

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 1, failure_count: 0 });
    expect(sentTokens(0)).toEqual(["fcm-token-first"]);
  });

  it("2 台のうち 1 台だけ失敗した配送を、全台成功として報告しない", async () => {
    await registerTwoDevices();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });
    context.failNextPushForToken("fcm-token-second");

    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(201);
    expect(response.body.delivery).toEqual({ success_count: 1, failure_count: 1 });

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(response.body.id)
      .get();
    expect(stored.get("delivery").failureCount).toBe(1);
    expect(stored.get("delivery").errors).toEqual(["messaging/invalid-registration-token"]);
  });

  it("取り消しは取り消し時点の配送先へ届ける (pro で登録した後に失効すると 1 台だけになる)", async () => {
    await registerTwoDevices();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);
    expect(sentTokens(0)).toEqual(["fcm-token-first", "fcm-token-second"]);

    await userRef(context.deps.firestore, context.uid).update({ plan: "free" });
    const canceled = await request(externalApi)
      .delete(`/v1/alarms/${created.body.id}`)
      .set("authorization", `Bearer ${issued.token}`)
      .expect(200);
    expect(canceled.body.delivery).toEqual({ success_count: 1, failure_count: 0 });
    expect(sentTokens(1)).toEqual(["fcm-token-first"]);
  });
});

describe("アラーム履歴", () => {
  it("アプリ向け API から新しい順に取得できる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const first = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "first" })
      .expect(201);
    context.setNow(new Date(TEST_NOW.getTime() + 1000));
    const second = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "second" })
      .expect(201);

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([
      second.body.id,
      first.body.id,
    ]);
  });

  it("cursor で続きを取得できる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    // 無料プランは 3 件で cursor を無視するため、cursor によるページングは pro プラン前提で確かめる
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });
    const ids: string[] = [];
    for (const index of [0, 1, 2]) {
      context.setNow(new Date(TEST_NOW.getTime() + index * 1000));
      const created = await request(externalApi)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT), title: `alarm-${index}` })
        .expect(201);
      ids.push(created.body.id);
    }

    const first = await request(appApi)
      .get("/v1/alarms?limit=2")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(first.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([ids[2], ids[1]]);
    expect(first.body.next_cursor).not.toBeNull();

    const second = await request(appApi)
      .get(`/v1/alarms?limit=2&cursor=${first.body.next_cursor}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(second.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([ids[0]]);
    expect(second.body.next_cursor).toBeNull();
  });

  it("形式が不正な cursor は 400", async () => {
    await request(appApi)
      .get("/v1/alarms?cursor=not-a-cursor")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(400);
    // Firestore の Timestamp の範囲を外れる時刻
    const outOfRange = Buffer.from("9007199254740991:x", "utf8").toString("base64url");
    await request(appApi)
      .get(`/v1/alarms?cursor=${outOfRange}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(400);
    // ドキュメント id として使えない文字を含む
    const invalidId = Buffer.from("0:a/b", "utf8").toString("base64url");
    await request(appApi)
      .get(`/v1/alarms?cursor=${invalidId}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(400);
  });

  it("cursor のアラームが削除されていても続きを辿れる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    // 無料プランは 3 件で cursor を無視するため、cursor によるページングは pro プラン前提で確かめる
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });
    const ids: string[] = [];
    for (const index of [0, 1, 2]) {
      context.setNow(new Date(TEST_NOW.getTime() + index * 1000));
      const created = await request(externalApi)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT) })
        .expect(201);
      ids.push(created.body.id);
    }
    const first = await request(appApi)
      .get("/v1/alarms?limit=2")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);

    // cursor が指すアラームが削除されても、残りを辿れる
    await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(ids[1])
      .delete();

    const second = await request(appApi)
      .get(`/v1/alarms?limit=2&cursor=${first.body.next_cursor}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(second.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([ids[0]]);
  });

  it("limit が範囲外なら 400", async () => {
    await request(appApi)
      .get("/v1/alarms?limit=0")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(400);
  });

  it("各要素に delivery と updated_at が含まれる", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0]).toMatchObject({
      id: created.body.id,
      delivery: { success_count: 1, failure_count: 0 },
      updated_at: TEST_NOW.toISOString(),
      device_reports: [],
    });
  });

  it("無料プランは直近 3 件までで、cursor を渡しても next_cursor は常に null", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    const ids: string[] = [];
    for (const index of [0, 1, 2, 3]) {
      context.setNow(new Date(TEST_NOW.getTime() + index * 1000));
      const created = await request(externalApi)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT), title: `alarm-${index}` })
        .expect(201);
      ids.push(created.body.id);
    }

    const response = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(response.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([
      ids[3],
      ids[2],
      ids[1],
    ]);
    expect(response.body.next_cursor).toBeNull();

    // 形式として妥当な cursor でも、無料プランでは先頭ページに固定する
    const validCursor = Buffer.from("0:some-id", "utf8").toString("base64url");
    const withCursor = await request(appApi)
      .get(`/v1/alarms?cursor=${validCursor}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(withCursor.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([
      ids[3],
      ids[2],
      ids[1],
    ]);
    expect(withCursor.body.next_cursor).toBeNull();

    const limited = await request(appApi)
      .get("/v1/alarms?limit=1")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(limited.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([ids[3]]);
  });

  it("pro プランは全件返り、limit を渡すと next_cursor が返る", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({ plan: "pro", proExpiresAt: null });
    const ids: string[] = [];
    for (const index of [0, 1, 2, 3]) {
      context.setNow(new Date(TEST_NOW.getTime() + index * 1000));
      const created = await request(externalApi)
        .post("/v1/alarms")
        .set("authorization", `Bearer ${issued.token}`)
        .send({ fire_at: toIso8601Seconds(FIRE_AT), title: `alarm-${index}` })
        .expect(201);
      ids.push(created.body.id);
    }

    const all = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(all.body.alarms).toHaveLength(4);
    expect(all.body.next_cursor).toBeNull();

    const paged = await request(appApi)
      .get("/v1/alarms?limit=2")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(paged.body.alarms).toHaveLength(2);
    expect(paged.body.next_cursor).not.toBeNull();
  });
});

describe("端末からの反映結果の報告", () => {
  async function createAlarm(): Promise<{ id: string; token: string }> {
    await registerDevice();
    const issued = await issueApiToken();
    const created = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(201);
    return { id: created.body.id, token: issued.token };
  }

  function postDeviceReport(alarmId: string, body: Record<string, unknown>) {
    return request(appApi)
      .post(`/v1/alarms/${alarmId}/device-reports`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send(body);
  }

  it("報告を送ると deviceReports に保存され、GET /v1/alarms の device_reports に出る (reported_at は出ない)", async () => {
    const { id } = await createAlarm();
    const response = await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);
    expect(response.body).toEqual({ alarm_id: id, device_id: "device-1" });

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([
      {
        device_id: "device-1",
        action: "schedule",
        result: "applied",
        error: null,
        occurred_at: "2026-09-02T00:00:10.000Z",
      },
    ]);
  });

  it("同じ報告を 2 回送っても 1 件のまま (冪等)。内容を変えて送ると上書きされる", async () => {
    const { id } = await createAlarm();
    const base = {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    };
    await postDeviceReport(id, base).expect(200);
    await postDeviceReport(id, base).expect(200);

    const alarmRef = userRef(context.deps.firestore, context.uid).collection(collections.alarms).doc(id);
    const afterRepeat = await alarmRef.get();
    expect(Object.keys(afterRepeat.get("deviceReports"))).toEqual(["device-1"]);

    await postDeviceReport(id, { ...base, result: "failed", error: "AlarmKit denied" }).expect(200);
    const afterOverwrite = await alarmRef.get();
    expect(Object.keys(afterOverwrite.get("deviceReports"))).toEqual(["device-1"]);
    expect(afterOverwrite.get("deviceReports")["device-1"]).toMatchObject({
      result: "failed",
      error: "AlarmKit denied",
    });
  });

  it("存在しないアラームへの報告は 404、alarmId が UUID でなければ 400、body 不正は 400", async () => {
    const { id } = await createAlarm();
    const validBody = {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    };
    const notFound = await postDeviceReport(
      "00000000-0000-4000-8000-000000000000",
      validBody,
    ).expect(404);
    expect(notFound.body.error.code).toBe("alarm_not_found");

    await postDeviceReport("not-a-uuid", validBody).expect(400);
    await postDeviceReport(id, { ...validBody, result: "ok" }).expect(400);
  });

  it("大文字の UUID で報告しても小文字のアラームに届く", async () => {
    const { id } = await createAlarm();
    const response = await postDeviceReport(id.toUpperCase(), {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);
    expect(response.body.alarm_id).toBe(id);

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(id)
      .get();
    expect(stored.get("deviceReports")).toHaveProperty("device-1");
  });

  it("登録していない device_id で報告すると 404 device_not_found、GET の device_reports は空のまま", async () => {
    const { id } = await createAlarm();
    const response = await postDeviceReport(id, {
      device_id: "device-unregistered",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(404);
    expect(response.body.error.code).toBe("device_not_found");

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([]);
  });

  it("報告を保存した後に外部 API で再スケジュールすると device_reports が空になる。古い fire_at の報告は 409 で弾かれ、新しい fire_at の報告は入る", async () => {
    const { id, token } = await createAlarm();
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    const rescheduled = new Date(FIRE_AT.getTime() + 60 * 60 * 1000);
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${token}`)
      .send({ id, fire_at: toIso8601Seconds(rescheduled), title: "Deploy finished" })
      .expect(200);

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([]);
    // 再スケジュールの push の結果 (端末 1 台への配送) が、前の登録の配送結果に上書きされず反映されている
    expect(history.body.alarms[0].delivery).toEqual({ success_count: 1, failure_count: 0 });

    const rescheduledAlarm = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(id)
      .get();
    // 再スケジュールの配送が記録されている (前の登録の delivery.sentAt が引き継がれて null のままになっていない)
    expect(rescheduledAlarm.get("delivery").sentAt).not.toBeNull();

    // 再スケジュール前の登録に対する報告が遅れて届いた場合。現在の登録の fireAt と一致しないため 409 で弾き、書き込まない
    const stale = await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:20Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(409);
    expect(stale.body.error.code).toBe("alarm_revision_mismatch");

    const afterStale = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(afterStale.body.alarms[0].device_reports).toEqual([]);

    // 現在の登録の fireAt と一致する報告は受け付ける
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:30Z",
      fire_at: toIso8601Seconds(rescheduled),
    }).expect(200);

    const afterCurrent = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(afterCurrent.body.alarms[0].device_reports).toHaveLength(1);
  });

  it("fire_at が現在の登録と 1 時間ずれた schedule 報告は 409 alarm_revision_mismatch、deviceReports は空のまま", async () => {
    const { id } = await createAlarm();
    const mismatched = new Date(FIRE_AT.getTime() + 60 * 60 * 1000);
    const response = await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(mismatched),
    }).expect(409);
    expect(response.body.error.code).toBe("alarm_revision_mismatch");

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(id)
      .get();
    expect(stored.get("deviceReports")).toEqual({});
  });

  it("action が schedule で fire_at を省くと 400 invalid_argument", async () => {
    const { id } = await createAlarm();
    const response = await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
    }).expect(400);
    expect(response.body.error.code).toBe("invalid_argument");
  });

  it("action が cancel なら fire_at が無くても 200 で device_reports に出る", async () => {
    const { id } = await createAlarm();
    const response = await postDeviceReport(id, {
      device_id: "device-1",
      action: "cancel",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
    }).expect(200);
    expect(response.body).toEqual({ alarm_id: id, device_id: "device-1" });

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([
      {
        device_id: "device-1",
        action: "cancel",
        result: "applied",
        error: null,
        occurred_at: "2026-09-02T00:00:10.000Z",
      },
    ]);
  });

  it("報告を保存した後に外部 API で同じ内容を再送しても device_reports は残る", async () => {
    const { id, token } = await createAlarm();
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${token}`)
      .send({ id, fire_at: toIso8601Seconds(FIRE_AT), title: "Deploy finished" })
      .expect(200);

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(id)
      .get();
    expect(Object.keys(stored.get("deviceReports"))).toEqual(["device-1"]);
  });

  it("報告を保存した後に DELETE で取り消しても device_reports は残る", async () => {
    const { id, token } = await createAlarm();
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    const response = await request(externalApi)
      .delete(`/v1/alarms/${id}`)
      .set("authorization", `Bearer ${token}`)
      .expect(200);
    expect(response.body.status).toBe("canceled");

    const stored = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .doc(id)
      .get();
    expect(stored.get("status")).toBe("canceled");
    expect(Object.keys(stored.get("deviceReports"))).toEqual(["device-1"]);
  });

  it("occurred_at が新しい失敗報告の後に古い成功報告が届いても、失敗のまま残る (200 は返す)", async () => {
    const { id } = await createAlarm();
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "failed",
      error: "AlarmKit denied",
      occurred_at: "2026-09-02T00:00:20Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    const response = await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);
    // 古い報告でも、端末はキューから消してよいので通常どおり 200 を返す
    expect(response.body).toEqual({ alarm_id: id, device_id: "device-1" });

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([
      {
        device_id: "device-1",
        action: "schedule",
        result: "failed",
        error: "AlarmKit denied",
        occurred_at: "2026-09-02T00:00:20.000Z",
      },
    ]);
  });

  it("occurred_at が古い報告の後に新しい報告が届くと上書きされる", async () => {
    const { id } = await createAlarm();
    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "failed",
      error: "AlarmKit denied",
      occurred_at: "2026-09-02T00:00:10Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    await postDeviceReport(id, {
      device_id: "device-1",
      action: "schedule",
      result: "applied",
      occurred_at: "2026-09-02T00:00:20Z",
      fire_at: toIso8601Seconds(FIRE_AT),
    }).expect(200);

    const history = await request(appApi)
      .get("/v1/alarms")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .expect(200);
    expect(history.body.alarms[0].device_reports).toEqual([
      {
        device_id: "device-1",
        action: "schedule",
        result: "applied",
        error: null,
        occurred_at: "2026-09-02T00:00:20.000Z",
      },
    ]);
  });
});

describe("匿名アカウントの統合", () => {
  /**
   * 匿名アカウント側に端末・API トークン・アラーム・利用数を書き込む (アプリの匿名認証で使っていた状態)。
   * 端末の既定の updatedAt は TEST_NOW で、Apple 側で同じ端末を登録し直した値との新旧を比べるテストだけが古い日時を渡す
   */
  async function seedAnonymousAccount(deviceId = "device-anonymous", updatedAt = TEST_NOW): Promise<void> {
    const anonymousUser = userRef(context.deps.firestore, ANONYMOUS_UID);
    const batch = context.deps.firestore.batch();
    batch.set(anonymousUser, {
      plan: "free",
      monthlyUsage: { month: "2026-09", scheduledAlarmCount: 7 },
      createdAt: Timestamp.fromDate(TEST_NOW),
      updatedAt: Timestamp.fromDate(TEST_NOW),
    });
    batch.set(anonymousUser.collection(collections.devices).doc(deviceId), {
      fcmToken: "fcm-token-anonymous",
      platform: "ios",
      createdAt: Timestamp.fromDate(new Date("2026-08-01T00:00:00Z")),
      updatedAt: Timestamp.fromDate(updatedAt),
    });
    batch.set(anonymousUser.collection(collections.apiTokens).doc("token-anonymous"), { hash: "dummy-hash", revokedAt: null });
    batch.set(anonymousUser.collection(collections.alarms).doc("alarm-anonymous"), { title: "Deploy finished" });
    await batch.commit();
  }

  /**
   * 統合先 (VALID_ID_TOKEN) として統合を呼ぶ。統合元の既定は正しい匿名アカウントのトークンで、
   * 拒否の確認をするテストだけが別のトークンを渡す
   */
  function merge(anonymousIdToken: string = ANONYMOUS_ID_TOKEN) {
    return request(appApi)
      .post("/v1/account/merge")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({ anonymous_id_token: anonymousIdToken });
  }

  /** ユーザーに登録されている端末の device_id (昇順) */
  async function deviceIds(uid: string): Promise<string[]> {
    const snapshot = await userRef(context.deps.firestore, uid).collection(collections.devices).get();
    return snapshot.docs.map((doc) => doc.id).sort();
  }

  beforeEach(() => {
    context.setSignInProvider("apple.com");
  });

  it("匿名側の端末を Apple 側へ移し、API トークンと利用数は Apple 側のまま残して匿名アカウントを消す", async () => {
    await registerDevice("device-apple", "fcm-token-apple");
    const issued = await issueApiToken("apple-token");
    await seedAnonymousAccount();
    const mergedAt = new Date("2026-09-02T01:00:00Z");
    context.setNow(mergedAt);

    const response = await merge().expect(200);

    expect(response.body.moved_devices).toBe(1);
    expect(await deviceIds(context.uid)).toEqual(["device-anonymous", "device-apple"]);
    const moved = await userRef(context.deps.firestore, context.uid)
      .collection(collections.devices)
      .doc("device-anonymous")
      .get();
    expect(moved.get("fcmToken")).toBe("fcm-token-anonymous");
    // 無料プランの配送先 (最初に登録した 1 台) を Apple 側の端末から奪わないよう、移した時刻で登録したことにする
    expect((moved.get("createdAt") as Timestamp).toMillis()).toBe(mergedAt.getTime());
    const tokens = await userRef(context.deps.firestore, context.uid).collection(collections.apiTokens).get();
    expect(tokens.docs.map((doc) => doc.id)).toEqual([issued.id]);
    const appleUser = await userRef(context.deps.firestore, context.uid).get();
    expect(appleUser.get("monthlyUsage.scheduledAlarmCount")).toBe(0);

    expect(context.deletedAuthUids).toEqual([ANONYMOUS_UID]);
    expect((await userRef(context.deps.firestore, ANONYMOUS_UID).get()).exists).toBe(false);
    expect(await deviceIds(ANONYMOUS_UID)).toEqual([]);
    const anonymousTokens = await userRef(context.deps.firestore, ANONYMOUS_UID).collection(collections.apiTokens).get();
    expect(anonymousTokens.size).toBe(0);
  });

  it("Apple 側にドキュメントが無くても、端末を移してユーザードキュメントを作る", async () => {
    await seedAnonymousAccount();

    await merge().expect(200);

    expect(await deviceIds(context.uid)).toEqual(["device-anonymous"]);
    expect((await userRef(context.deps.firestore, context.uid).get()).get("plan")).toBe("free");
  });

  it("再送しても成功し、移した端末は変わらない (冪等)", async () => {
    await seedAnonymousAccount();
    await merge().expect(200);

    const response = await merge().expect(200);

    expect(response.body.moved_devices).toBe(0);
    expect(await deviceIds(context.uid)).toEqual(["device-anonymous"]);
  });

  it("同じ端末を Apple 側で登録し直した値の方が新しければ上書きしない", async () => {
    await seedAnonymousAccount("device-1", new Date("2026-09-01T00:00:00Z"));
    await registerDevice("device-1", "fcm-token-rotated");

    const response = await merge().expect(200);

    expect(response.body.moved_devices).toBe(0);
    const device = await userRef(context.deps.firestore, context.uid).collection(collections.devices).doc("device-1").get();
    expect(device.get("fcmToken")).toBe("fcm-token-rotated");
  });

  it("Apple 側の端末が上限に達していれば移さずに匿名アカウントを消す", async () => {
    for (let index = 0; index < MAX_DEVICES_PER_USER; index += 1) {
      await registerDevice(`device-${index}`, `fcm-token-${index}`);
    }
    await seedAnonymousAccount();

    const response = await merge().expect(200);

    expect(response.body.moved_devices).toBe(0);
    expect(await deviceIds(context.uid)).toHaveLength(MAX_DEVICES_PER_USER);
    expect(context.deletedAuthUids).toEqual([ANONYMOUS_UID]);
  });

  it("統合先が匿名アカウントなら 403 で何も変えない", async () => {
    context.setSignInProvider("anonymous");
    await seedAnonymousAccount();

    const response = await merge().expect(403);

    expect(response.body.error.code).toBe("merge_target_anonymous");
    expect(await deviceIds(ANONYMOUS_UID)).toEqual(["device-anonymous"]);
    expect(context.deletedAuthUids).toEqual([]);
  });

  it("統合元の ID トークンが検証できない・匿名でない・統合先と同じなら 400", async () => {
    await seedAnonymousAccount();

    const invalid = await merge("invalid").expect(400);
    expect(invalid.body.error.code).toBe("invalid_anonymous_id_token");
    // VALID_ID_TOKEN は統合先 (apple.com) 自身のトークン
    const identified = await merge(VALID_ID_TOKEN).expect(400);
    expect(identified.body.error.code).toBe("invalid_anonymous_id_token");
    await request(appApi)
      .post("/v1/account/merge")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
      .send({})
      .expect(400);

    expect(await deviceIds(ANONYMOUS_UID)).toEqual(["device-anonymous"]);
    expect(context.deletedAuthUids).toEqual([]);
  });

  it("統合先のアカウントが削除処理中なら 410 で匿名アカウントに触れない", async () => {
    await seedAnonymousAccount();
    await context.deps.firestore.collection(collections.deletedAccounts).doc(context.uid).set({
      [deletedAccountFields.requestedAt]: Timestamp.fromDate(TEST_NOW),
    });

    const response = await merge().expect(410);

    expect(response.body.error.code).toBe("account_deleted");
    expect(await deviceIds(ANONYMOUS_UID)).toEqual(["device-anonymous"]);
    expect(context.deletedAuthUids).toEqual([]);
  });
});
