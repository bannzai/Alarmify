import type { Server } from "node:http";
import { Timestamp } from "firebase-admin/firestore";
import type { TokenMessage } from "firebase-admin/messaging";
import request from "supertest";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createAppApi } from "../src/api/appApi.js";
import { createExternalApi } from "../src/api/externalApi.js";
import { toIso8601Seconds } from "../src/lib/push.js";
import { userRef } from "../src/lib/store.js";
import { collections } from "../src/schema/index.js";
import {
  clearFirestore,
  createTestContext,
  startTestServer,
  stopTestServer,
  TEST_NOW,
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
    .send({ device_id: deviceId, fcm_token: fcmToken })
    .expect(200);
}

async function issueApiToken(name = "github-actions"): Promise<{ id: string; token: string }> {
  const response = await request(appApi)
    .post("/v1/api-tokens")
    .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
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
    const response = await request(appApi).post("/v1/api-tokens").send({}).expect(401);
    expect(response.body.error.code).toBe("unauthenticated");
  });

  it("ID トークンが不正なら 401", async () => {
    await request(appApi)
      .post("/v1/api-tokens")
      .set("authorization", "Bearer invalid")
      .send({})
      .expect(401);
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
      .send({ name: "second" })
      .expect(403);
    expect(response.body.error.code).toBe("plan_limit_exceeded");
  });

  it("失効させたトークンは一覧から消え、再度発行できる", async () => {
    const issued = await issueApiToken();
    await request(appApi)
      .delete(`/v1/api-tokens/${issued.id}`)
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .expect(204);
    const list = await request(appApi)
      .get("/v1/api-tokens")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .expect(200);
    expect(list.body.api_tokens).toHaveLength(0);
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
    // 保持期間 30 日
    expect((stored.get("expiresAt") as Timestamp).toMillis()).toBe(
      TEST_NOW.getTime() + 30 * 24 * 60 * 60 * 1000,
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
      .expect(204);
    await request(externalApi)
      .post("/v1/alarms")
      .set("authorization", `Bearer ${issued.token}`)
      .send({ fire_at: toIso8601Seconds(FIRE_AT) })
      .expect(401);
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

  it("存在しないアラームの取り消しは 404", async () => {
    await registerDevice();
    const issued = await issueApiToken();
    await request(externalApi)
      .delete("/v1/alarms/unknown-alarm")
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
      .expect(200);
    expect(history.body.alarms.map((alarm: { id: string }) => alarm.id)).toEqual([
      second.body.id,
      first.body.id,
    ]);
  });

  it("limit が範囲外なら 400", async () => {
    await request(appApi)
      .get("/v1/alarms?limit=0")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .expect(400);
  });
});
