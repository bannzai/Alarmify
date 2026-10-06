import type { Server } from "node:http";
import { Timestamp } from "firebase-admin/firestore";
import request from "supertest";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createAppApi } from "../src/api/appApi.js";
import { APP_CHECK_HEADER } from "../src/lib/appCheck.js";
import { CONTACT_INQUIRY_SLACK_CHANNEL, escapeSlackText } from "../src/lib/contactInquiry.js";
import { collections, contactInquirySchema, deletedAccountFields } from "../src/schema/index.js";
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

let context: TestContext;
let appApi: Server;

/** 受け付けられる送信内容。各テストは一部の項目だけを差し替えて使う */
const VALID_INQUIRY = {
  inquiry_type: "bug",
  content: "アラームが鳴りません",
  email_address: "user@example.com",
  app_version: "1.2.0",
};

/** 有効な ID トークンと App Check トークンを付けて POST /v1/contact-inquiries を送る */
function postInquiry(body: Record<string, unknown>) {
  return request(appApi)
    .post("/v1/contact-inquiries")
    .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
    .set(APP_CHECK_HEADER, VALID_APP_CHECK_TOKEN)
    .send(body);
}

beforeEach(async () => {
  await clearFirestore();
  context = createTestContext();
  appApi = await startTestServer(createAppApi(context.deps));
});

afterEach(async () => {
  await stopTestServer(appApi);
});

describe("お問い合わせ", () => {
  it("保存して Slack へ通知する", async () => {
    const response = await postInquiry(VALID_INQUIRY).expect(201);

    const snapshot = await context.deps.firestore
      .collection(collections.contactInquiries)
      .doc(response.body.id)
      .get();
    const inquiry = contactInquirySchema.parse(snapshot.data());
    expect(inquiry).toEqual({
      uid: context.uid,
      inquiryType: "bug",
      content: "アラームが鳴りません",
      emailAddress: "user@example.com",
      appVersion: "1.2.0",
      createdAt: Timestamp.fromDate(TEST_NOW),
      expiresAt: Timestamp.fromDate(new Date("2027-09-02T00:00:00Z")),
    });

    expect(context.slackMessages).toHaveLength(1);
    expect(context.slackMessages[0].channel).toBe(CONTACT_INQUIRY_SLACK_CHANNEL);
    expect(context.slackMessages[0].text).toContain("[種別] バグ・不具合");
    expect(context.slackMessages[0].text).toContain(`[UserID] ${context.uid}`);
    expect(context.slackMessages[0].text).toContain("[Email] user@example.com");
    expect(context.slackMessages[0].text).toContain("[AppVersion] 1.2.0");
    expect(context.slackMessages[0].text).toContain(`~2FcontactInquiries~2F${response.body.id}`);
    expect(context.slackMessages[0].text).toContain("アラームが鳴りません");
  });

  it("アプリのバージョンが無くても受け付ける", async () => {
    const response = await postInquiry({ ...VALID_INQUIRY, app_version: undefined }).expect(201);

    const snapshot = await context.deps.firestore
      .collection(collections.contactInquiries)
      .doc(response.body.id)
      .get();
    expect(snapshot.get("appVersion")).toBeNull();
    expect(context.slackMessages[0].text).toContain("[AppVersion] 不明");
  });

  it("Slack への通知に失敗しても保存した問い合わせは残し 201 を返す", async () => {
    context.failNextSlackMessage();

    const response = await postInquiry(VALID_INQUIRY).expect(201);

    const snapshot = await context.deps.firestore
      .collection(collections.contactInquiries)
      .doc(response.body.id)
      .get();
    expect(snapshot.exists).toBe(true);
  });

  it("本文の Slack の制御文字はエスケープして通知する", async () => {
    await postInquiry({ ...VALID_INQUIRY, content: "<!channel> & <https://example.com|link>" }).expect(201);

    expect(context.slackMessages[0].text).toContain("&lt;!channel&gt; &amp; &lt;https://example.com|link&gt;");
    expect(context.slackMessages[0].text).not.toContain("<!channel>");
  });

  it.each([
    ["種別が不正", { ...VALID_INQUIRY, inquiry_type: "praise" }],
    ["本文が空白だけ", { ...VALID_INQUIRY, content: "   " }],
    ["本文が上限を超える", { ...VALID_INQUIRY, content: "a".repeat(4001) }],
    ["メールアドレスの形式が不正", { ...VALID_INQUIRY, email_address: "not-an-email" }],
  ])("%s なら 400 で保存も通知もしない", async (_label, body) => {
    const response = await postInquiry(body).expect(400);
    expect(response.body.error.code).toBe("invalid_argument");

    const snapshot = await context.deps.firestore.collection(collections.contactInquiries).get();
    expect(snapshot.size).toBe(0);
    expect(context.slackMessages).toHaveLength(0);
  });

  it("1 時間に 5 件を超えると 429", async () => {
    for (let index = 0; index < 5; index += 1) {
      await postInquiry(VALID_INQUIRY).expect(201);
    }

    const response = await postInquiry(VALID_INQUIRY).expect(429);
    expect(response.body.error.code).toBe("rate_limited");
    expect(context.slackMessages).toHaveLength(5);
  });

  it("アカウントが削除処理中なら 410 で保存も通知もしない", async () => {
    await context.deps.firestore.collection(collections.deletedAccounts).doc(context.uid).set({
      [deletedAccountFields.requestedAt]: Timestamp.fromDate(TEST_NOW),
    });

    const response = await postInquiry(VALID_INQUIRY).expect(410);

    expect(response.body.error.code).toBe("account_deleted");
    const snapshot = await context.deps.firestore.collection(collections.contactInquiries).get();
    expect(snapshot.size).toBe(0);
    expect(context.slackMessages).toHaveLength(0);
  });

  it("App Check トークンが無ければ 401", async () => {
    await request(appApi)
      .post("/v1/contact-inquiries")
      .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
      .send(VALID_INQUIRY)
      .expect(401);
  });
});

describe("escapeSlackText", () => {
  it("& < > だけを置き換える", () => {
    expect(escapeSlackText("a & <b> c")).toBe("a &amp; &lt;b&gt; c");
  });
});
