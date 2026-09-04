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
import { collections } from "../src/schema/index.js";
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

  it("無料プランの月 20 件を超えると 403", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      monthlyUsage: { month: "2026-09", scheduledAlarmCount: 20 },
    });
    const response = await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(403);
    expect(response.body.error.code).toBe("plan_limit_exceeded");
  });

  it("月が変わると月間の登録数を数え直す", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await userRef(context.deps.firestore, context.uid).update({
      monthlyUsage: { month: "2026-08", scheduledAlarmCount: 20 },
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
});
