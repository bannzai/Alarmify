import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { deleteExpiredAlarms } from "../src/lib/cleanup.js";
import { userRef } from "../src/lib/store.js";
import { collections } from "../src/schema/index.js";
import { clearFirestore, createTestContext, TEST_NOW, type TestContext } from "./helpers.js";

let context: TestContext;

async function seedAlarm(id: string, expiresAt: Date): Promise<void> {
  await userRef(context.deps.firestore, context.uid)
    .collection(collections.alarms)
    .doc(id)
    .set({
      title: null,
      fireAt: Timestamp.fromDate(TEST_NOW),
      status: "scheduled",
      tokenId: "token-1",
      createdAt: Timestamp.fromDate(TEST_NOW),
      updatedAt: Timestamp.fromDate(TEST_NOW),
      expiresAt: Timestamp.fromDate(expiresAt),
      delivery: { sentAt: null, successCount: 0, failureCount: 0, errors: [] },
    });
}

beforeEach(async () => {
  await clearFirestore();
  context = createTestContext();
});

describe("保持期間を過ぎたアラームの削除", () => {
  it("expiresAt を過ぎたものだけを削除し、再実行しても結果が変わらない (冪等)", async () => {
    await seedAlarm("expired", new Date(TEST_NOW.getTime() - 1000));
    await seedAlarm("alive", new Date(TEST_NOW.getTime() + 1000));

    expect(await deleteExpiredAlarms(context.deps)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps)).toBe(0);

    const remaining = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(remaining.docs.map((doc) => doc.id)).toEqual(["alive"]);
  });

  it("1 回の実行で処理するバッチ数に上限を設ける", async () => {
    await seedAlarm("expired-1", new Date(TEST_NOW.getTime() - 1000));
    await seedAlarm("expired-2", new Date(TEST_NOW.getTime() - 1000));
    const options = { batchSize: 1, maxBatches: 1 };
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(0);
  });

  it("バッチサイズを超える件数も 1 回の実行で削除しきる", async () => {
    for (const index of [1, 2, 3, 4, 5]) {
      await seedAlarm(`expired-${index}`, new Date(TEST_NOW.getTime() - 1000));
    }
    expect(await deleteExpiredAlarms(context.deps, { batchSize: 2, maxBatches: 10 })).toBe(5);
    const remaining = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(remaining.empty).toBe(true);
  });
});
