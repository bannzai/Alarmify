import { beforeEach, describe, expect, it } from "vitest";
import {
  BUDGET_SLACK_CHANNEL,
  budgetMessageSchema,
  budgetNotificationRef,
  formatBudgetSlackText,
  notifyBudgetThreshold,
  type BudgetAlertDeps,
  type BudgetMessage,
} from "../src/lib/budgetAlert.js";
import { budgetNotificationFields } from "../src/schema/index.js";
import { clearFirestore, TEST_NOW, testFirestore } from "./helpers.js";

/** Cloud Billing が付けるメッセージ属性 (budgetId は予算の UUID) */
const ATTRIBUTES = {
  billingAccountId: "01D4EE-079462-DFD6EC",
  budgetId: "de72f49d-779b-4945-a127-4d6ce8def0bb",
  schemaVersion: "1.0",
};

/** 公式ドキュメントの例に合わせた予算通知の本文。閾値を超えていない状態を既定にする */
function budgetMessage(overrides: Partial<BudgetMessage> = {}): BudgetMessage {
  return {
    budgetDisplayName: "budget-alarmify-prod",
    costAmount: 140.321,
    costIntervalStart: "2026-09-01T00:00:00Z",
    budgetAmount: 10000,
    currencyCode: "JPY",
    ...overrides,
  };
}

let posted: { channel: string; text: string }[];
let failNextPost: boolean;
let deps: BudgetAlertDeps;

beforeEach(async () => {
  await clearFirestore();
  posted = [];
  failNextPost = false;
  deps = {
    firestore: testFirestore(),
    postSlackMessage: async (channel, text) => {
      if (failNextPost) {
        failNextPost = false;
        throw new Error("slack unavailable");
      }
      posted.push({ channel, text });
    },
    now: () => TEST_NOW,
  };
});

async function storedRecord() {
  return (await budgetNotificationRef(deps.firestore, ATTRIBUTES.budgetId).get()).data();
}

describe("予算通知の形式", () => {
  it("公式ドキュメントの例を受け付け、知らないフィールドは読み飛ばす", () => {
    const parsed = budgetMessageSchema.parse({
      budgetDisplayName: "My Personal Budget",
      costAmount: 140.321,
      costIntervalStart: "2021-02-01T08:00:00Z",
      budgetAmount: 152.557,
      budgetAmountType: "SPECIFIED_AMOUNT",
      alertThresholdExceeded: 0.9,
      forecastThresholdExceeded: 0.2,
      currencyCode: "USD",
    });
    expect(parsed.alertThresholdExceeded).toBe(0.9);
    expect(parsed.forecastThresholdExceeded).toBe(0.2);
  });

  it("必須フィールドが欠けていれば受け付けない", () => {
    expect(budgetMessageSchema.safeParse({ budgetDisplayName: "x" }).success).toBe(false);
  });
});

describe("Slack の本文", () => {
  it("閾値・支出・予算・集計期間と予算画面へのリンクを含む", () => {
    const text = formatBudgetSlackText(
      budgetMessage({ costAmount: 5123, alertThresholdExceeded: 0.5 }),
      0.5,
      ATTRIBUTES,
    );
    expect(text).toContain("budget-alarmify-prod");
    expect(text).toContain("50%");
    expect(text).toContain("5,123");
    expect(text).toContain("10,000");
    expect(text).toContain("2026-09-01T00:00:00Z");
    expect(text).toContain(`https://console.cloud.google.com/billing/${ATTRIBUTES.billingAccountId}/budgets`);
  });

  it("課金アカウント ID が無ければリンクを付けない", () => {
    expect(formatBudgetSlackText(budgetMessage(), 0.5, { budgetId: ATTRIBUTES.budgetId })).not.toContain(
      "console.cloud.google.com",
    );
  });
});

describe("予算通知の転送", () => {
  it("閾値を超えていない通常の状態報告は投稿せず、記録も残さない", async () => {
    expect(await notifyBudgetThreshold(deps, { data: budgetMessage(), attributes: ATTRIBUTES })).toBe(
      "no_threshold",
    );
    expect(posted).toEqual([]);
    expect(await storedRecord()).toBeUndefined();
  });

  it("同じ閾値は同じ集計期間に 1 回だけ投稿し、閾値が上がった時に再び投稿する (冪等)", async () => {
    const exceeded50 = { data: budgetMessage({ alertThresholdExceeded: 0.5 }), attributes: ATTRIBUTES };
    const exceeded90 = { data: budgetMessage({ alertThresholdExceeded: 0.9 }), attributes: ATTRIBUTES };

    expect(await notifyBudgetThreshold(deps, exceeded50)).toBe("posted");
    expect(await notifyBudgetThreshold(deps, exceeded50)).toBe("already_notified");
    expect(await notifyBudgetThreshold(deps, exceeded90)).toBe("posted");
    expect(await notifyBudgetThreshold(deps, exceeded90)).toBe("already_notified");
    expect(await notifyBudgetThreshold(deps, exceeded50)).toBe("already_notified");

    expect(posted.map((post) => post.channel)).toEqual([BUDGET_SLACK_CHANNEL, BUDGET_SLACK_CHANNEL]);
    expect(posted[0].text).toContain("50%");
    expect(posted[1].text).toContain("90%");
    expect(await storedRecord()).toMatchObject({
      [budgetNotificationFields.costIntervalStart]: "2026-09-01T00:00:00Z",
      [budgetNotificationFields.notifiedThresholdPercent]: 0.9,
    });
  });

  it("集計期間が変われば同じ閾値でも投稿する", async () => {
    await notifyBudgetThreshold(deps, {
      data: budgetMessage({ alertThresholdExceeded: 0.9 }),
      attributes: ATTRIBUTES,
    });
    expect(
      await notifyBudgetThreshold(deps, {
        data: budgetMessage({ alertThresholdExceeded: 0.5, costIntervalStart: "2026-10-01T00:00:00Z" }),
        attributes: ATTRIBUTES,
      }),
    ).toBe("posted");
    expect(posted).toHaveLength(2);
    expect(await storedRecord()).toMatchObject({
      [budgetNotificationFields.costIntervalStart]: "2026-10-01T00:00:00Z",
      [budgetNotificationFields.notifiedThresholdPercent]: 0.5,
    });
  });

  it("Slack への投稿に失敗した通知は記録を残さず、次の通知で投稿し直す", async () => {
    const exceeded50 = { data: budgetMessage({ alertThresholdExceeded: 0.5 }), attributes: ATTRIBUTES };
    failNextPost = true;
    await expect(notifyBudgetThreshold(deps, exceeded50)).rejects.toThrow("slack unavailable");
    expect(await storedRecord()).toBeUndefined();

    expect(await notifyBudgetThreshold(deps, exceeded50)).toBe("posted");
    expect(posted).toHaveLength(1);
  });

  it("予算通知の形式に合わないメッセージは投稿しない", async () => {
    expect(await notifyBudgetThreshold(deps, { data: { hello: "world" }, attributes: ATTRIBUTES })).toBe("invalid");
    expect(await notifyBudgetThreshold(deps, { data: undefined, attributes: ATTRIBUTES })).toBe("invalid");
    expect(
      await notifyBudgetThreshold(deps, { data: budgetMessage({ alertThresholdExceeded: 0.5 }), attributes: {} }),
    ).toBe("invalid");
    expect(posted).toEqual([]);
  });
});
