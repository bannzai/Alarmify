import { getAuth, type Auth } from "firebase-admin/auth";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import {
  DELETION_MARKER_MINIMUM_AGE_MS,
  deleteUserAccount,
  handleDeleteAccount,
  sweepDeletedAccounts,
  type AccountDeletionDeps,
} from "../src/account/deleteAccount.js";
import { collections, deletedAccountFields } from "../src/schema/index.js";
import request from "supertest";
import { createAppApi } from "../src/api/appApi.js";
import {
  clearFirestore,
  createTestContext,
  PROJECT_ID,
  startTestServer,
  stopTestServer,
  TEST_NOW,
  testFirestore,
  VALID_ID_TOKEN,
} from "./helpers.js";

let deps: AccountDeletionDeps;
let auth: Auth;

/** sweep の対象になる、十分に古い目印の作成時刻 */
const staleRequestedAt = Timestamp.fromMillis(TEST_NOW.getTime() - DELETION_MARKER_MINIMUM_AGE_MS - 60_000);

function authEmulatorHost(): string {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (!host) {
    throw new Error("FIREBASE_AUTH_EMULATOR_HOST が未設定です。npm test から実行してください");
  }
  return host;
}

/** テスト間で状態を持ち越さないよう、Auth エミュレータの全ユーザーを消す */
async function clearAuth(): Promise<void> {
  const response = await fetch(
    `http://${authEmulatorHost()}/emulator/v1/projects/${PROJECT_ID}/accounts`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Auth エミュレータの初期化に失敗しました: ${response.status}`);
  }
}

/** Auth エミュレータで匿名ユーザーを作る (iOS アプリの匿名認証と同じ経路)。エミュレータは API キーを検証しない */
async function signUpAnonymously(): Promise<string> {
  const response = await fetch(
    `http://${authEmulatorHost()}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { localId: string };
  return body.localId;
}

/** アカウント削除で消えるべきデータ一式 (本体 + apiTokens / devices / alarms) を書き込む */
async function seedUserData(uid: string): Promise<void> {
  const userDocument = deps.firestore.collection(collections.users).doc(uid);
  const batch = deps.firestore.batch();
  batch.set(userDocument, { plan: "free" });
  batch.set(userDocument.collection(collections.apiTokens).doc("token1"), { hash: "dummy-hash" });
  batch.set(userDocument.collection(collections.devices).doc("device1"), { fcmToken: "dummy-fcm-token" });
  batch.set(userDocument.collection(collections.alarms).doc("alarm1"), { title: "Deploy finished" });
  await batch.commit();
}

/** ユーザー配下に残っているドキュメント数 (本体 + 3 サブコレクション) */
async function remainingDocumentCount(uid: string): Promise<number> {
  const userDocument = deps.firestore.collection(collections.users).doc(uid);
  const counts = await Promise.all(
    [collections.apiTokens, collections.devices, collections.alarms].map(
      async (subcollection) => (await userDocument.collection(subcollection).get()).size,
    ),
  );
  return ((await userDocument.get()).exists ? 1 : 0) + counts.reduce((total: number, count: number) => total + count, 0);
}

function marker(uid: string) {
  return deps.firestore.collection(collections.deletedAccounts).doc(uid);
}

async function authUserExists(uid: string): Promise<boolean> {
  try {
    await auth.getUser(uid);
    return true;
  } catch {
    return false;
  }
}

beforeEach(async () => {
  await Promise.all([clearFirestore(), clearAuth()]);
  // testFirestore() が既定のアプリを初期化する。getAuth() はその後でないと既定のアプリを見つけられない
  const firestore = testFirestore();
  auth = getAuth();
  deps = { firestore, auth };
});

describe("アカウント削除", () => {
  it("Firestore のユーザー配下と Auth のユーザーを削除し、書き込みを拒否するための目印を残す", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    expect(await remainingDocumentCount(uid)).toBe(4);

    const result = await deleteUserAccount(deps, uid);

    expect(result).toEqual({ authUserExisted: true, userDocumentExisted: true });
    expect(await remainingDocumentCount(uid)).toBe(0);
    expect(await authUserExists(uid)).toBe(false);
    expect((await marker(uid).get()).exists).toBe(true);
  });

  it("削除済みの uid で再実行しても成功する (冪等)", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    await deleteUserAccount(deps, uid);

    const result = await deleteUserAccount(deps, uid);

    expect(result).toEqual({ authUserExisted: false, userDocumentExisted: false });
    expect(await remainingDocumentCount(uid)).toBe(0);
  });

  it("Callable は ID トークンの uid だけを削除し、未認証は unauthenticated で拒否する", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);

    await expect(handleDeleteAccount(deps, { auth: undefined })).rejects.toMatchObject({
      code: "unauthenticated",
    });
    expect(await remainingDocumentCount(uid)).toBe(4);
    expect(await authUserExists(uid)).toBe(true);

    const result = await handleDeleteAccount(deps, { auth: { uid } });

    expect(result).toEqual({ userId: uid, authUserExisted: true, userDocumentExisted: true });
    expect(await remainingDocumentCount(uid)).toBe(0);
    expect(await authUserExists(uid)).toBe(false);
  });

  it("目印がある間は、削除前の ID トークンで届いた書き込みがデータを作り直せない", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    await deleteUserAccount(deps, uid);
    const context = createTestContext(uid);
    const appApi = await startTestServer(createAppApi(context.deps));
    try {
      const device = await request(appApi)
        .post("/v1/devices")
        .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
        .send({ device_id: "device-1", fcm_token: "fcm-token-1" })
        .expect(410);
      expect(device.body.error.code).toBe("account_deleted");
      const token = await request(appApi)
        .post("/v1/api-tokens")
        .set("authorization", `Bearer ${VALID_ID_TOKEN}`)
        .send({ name: "github-actions" })
        .expect(410);
      expect(token.body.error.code).toBe("account_deleted");
    } finally {
      await stopTestServer(appApi);
    }
    expect(await remainingDocumentCount(uid)).toBe(0);
  });
});

describe("削除の掃除 (sweep)", () => {
  it("Auth の削除後に残ったデータを消して目印を外し、目印の無いアカウントには触れない", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    await marker(uid).set({ [deletedAccountFields.requestedAt]: staleRequestedAt });
    await auth.deleteUser(uid);
    const untouched = await signUpAnonymously();
    await seedUserData(untouched);

    const result = await sweepDeletedAccounts(deps, TEST_NOW);

    expect(result).toEqual({ completed: 1, withdrawn: 0, failed: 0 });
    expect(await remainingDocumentCount(uid)).toBe(0);
    expect((await marker(uid).get()).exists).toBe(false);
    expect(await remainingDocumentCount(untouched)).toBe(4);
    expect(await authUserExists(untouched)).toBe(true);
  });

  it("Auth の削除が完了していない目印は、データに触れずに取り下げる", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    await marker(uid).set({ [deletedAccountFields.requestedAt]: staleRequestedAt });

    const result = await sweepDeletedAccounts(deps, TEST_NOW);

    expect(result).toEqual({ completed: 0, withdrawn: 1, failed: 0 });
    expect(await remainingDocumentCount(uid)).toBe(4);
    expect(await authUserExists(uid)).toBe(true);
    expect((await marker(uid).get()).exists).toBe(false);
  });

  it("有効な ID トークンが残り得る間 (目印を置いてから 2 時間) は触れない", async () => {
    const uid = await signUpAnonymously();
    await seedUserData(uid);
    await marker(uid).set({ [deletedAccountFields.requestedAt]: Timestamp.fromDate(TEST_NOW) });

    const result = await sweepDeletedAccounts(deps, TEST_NOW);

    expect(result).toEqual({ completed: 0, withdrawn: 0, failed: 0 });
    expect((await marker(uid).get()).exists).toBe(true);
    expect(await remainingDocumentCount(uid)).toBe(4);
  });

  it("読んだ後に置き直された目印は消さない", async () => {
    const uid = await signUpAnonymously();
    await marker(uid).set({ [deletedAccountFields.requestedAt]: staleRequestedAt });
    const stale = await marker(uid).get();
    await marker(uid).set({ [deletedAccountFields.requestedAt]: Timestamp.fromDate(TEST_NOW) });

    await expect(marker(uid).delete({ lastUpdateTime: stale.updateTime })).rejects.toThrow();
    expect((await marker(uid).get()).exists).toBe(true);
  });
});
