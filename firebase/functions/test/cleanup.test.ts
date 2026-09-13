import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { CLEANUP_TTL_GRACE_HOURS, deleteExpiredAlarms, deleteUnchanged } from "../src/lib/cleanup.js";
import { userRef } from "../src/lib/store.js";
import { collections } from "../src/schema/index.js";
import { clearFirestore, createTestContext, TEST_NOW, type TestContext } from "./helpers.js";

let context: TestContext;

const GRACE_MS = CLEANUP_TTL_GRACE_HOURS * 60 * 60 * 1000;
/** TTL の猶予を過ぎた期限切れ (TTL が消し残したとみなす) */
const OUTLIVED_TTL = new Date(TEST_NOW.getTime() - GRACE_MS - 1000);
/** 期限切れだが TTL の猶予の中 (TTL の削除待ち) */
const WITHIN_TTL_GRACE = new Date(TEST_NOW.getTime() - 1000);

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

describe("TTL が消し残した期限切れアラームの削除", () => {
  it("TTL の猶予を過ぎたものだけを削除し、再実行しても結果が変わらない (冪等)", async () => {
    await seedAlarm("outlived", OUTLIVED_TTL);
    await seedAlarm("within-grace", WITHIN_TTL_GRACE);
    await seedAlarm("alive", new Date(TEST_NOW.getTime() + 1000));

    expect(await deleteExpiredAlarms(context.deps)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps)).toBe(0);

    const remaining = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(remaining.docs.map((doc) => doc.id).sort()).toEqual(["alive", "within-grace"]);
  });

  it("猶予ちょうどの期限切れは削除の対象になる", async () => {
    await seedAlarm("at-grace", new Date(TEST_NOW.getTime() - GRACE_MS));
    expect(await deleteExpiredAlarms(context.deps)).toBe(1);
  });

  it("1 回の実行で処理するバッチ数に上限を設ける", async () => {
    await seedAlarm("outlived-1", OUTLIVED_TTL);
    await seedAlarm("outlived-2", OUTLIVED_TTL);
    const options = { batchSize: 1, maxBatches: 1 };
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(1);
    expect(await deleteExpiredAlarms(context.deps, options)).toBe(0);
  });

  it("問い合わせた後に更新されたアラームは削除しない", async () => {
    await seedAlarm("outlived", OUTLIVED_TTL);
    const alarmsRef = userRef(context.deps.firestore, context.uid).collection(collections.alarms);
    const snapshot = await alarmsRef.get();

    // 問い合わせの後に再スケジュールされた状況を作る
    await alarmsRef.doc("outlived").update({
      expiresAt: Timestamp.fromMillis(TEST_NOW.getTime() + 60_000),
    });

    expect(await deleteUnchanged(context.deps.firestore, snapshot.docs)).toBe(0);
    expect((await alarmsRef.doc("outlived").get()).exists).toBe(true);
  });

  it("WriteBatch の上限を超える batchSize は受け付けない", async () => {
    await expect(deleteExpiredAlarms(context.deps, { batchSize: 501 })).rejects.toThrow(RangeError);
    await expect(deleteExpiredAlarms(context.deps, { maxBatches: 0 })).rejects.toThrow(RangeError);
  });

  it("バッチサイズを超える件数も 1 回の実行で削除しきる", async () => {
    for (const index of [1, 2, 3, 4, 5]) {
      await seedAlarm(`outlived-${index}`, OUTLIVED_TTL);
    }
    expect(await deleteExpiredAlarms(context.deps, { batchSize: 2, maxBatches: 10 })).toBe(5);
    const remaining = await userRef(context.deps.firestore, context.uid)
      .collection(collections.alarms)
      .get();
    expect(remaining.empty).toBe(true);
  });
});
