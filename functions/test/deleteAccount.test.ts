import { readFileSync } from "node:fs";
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { deleteUserAccount, deletionMarkerMinimumAgeMs, sweepDeletedAccounts } from "../src/account/deleteAccount";
import {
  deletedAccountDocumentPath,
  deletedAccountsCollectionId,
  userDocumentPath,
  usersCollectionId,
  userSubcollectionIds,
  userSubcollectionPath,
} from "../src/schema/user";

/** ローカル専用のプロジェクト ID。実プロジェクトへ接続するテストを書かない (.claude/rules/firestore-db-rules.md) */
const projectId = "demo-alarmify";
const region = "asia-northeast1";

// deleteUserAccount は既定のアプリ (Functions 本体と同じ初期化) を使うため、テストでも既定のアプリを初期化する
const app = initializeApp({ projectId });
const firestore = getFirestore();
const auth = getAuth();

/** Functions エミュレータのポートは firebase.json を正とする */
const functionsPort = (
  JSON.parse(readFileSync(new URL("../../firebase.json", import.meta.url), "utf8")) as {
    emulators: { functions: { port: number } };
  }
).emulators.functions.port;
const deleteAccountUrl = `http://127.0.0.1:${functionsPort}/${projectId}/${region}/deleteAccount`;

/** Auth エミュレータで匿名ユーザーを作り、iOS アプリと同じ ID トークンを得る */
async function signUpAnonymously(): Promise<{ uid: string; idToken: string }> {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (host === undefined) {
    throw new Error("FIREBASE_AUTH_EMULATOR_HOST is not set. Run this test through `npm test`.");
  }
  const response = await fetch(
    `http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    }
  );
  const body = (await response.json()) as { localId: string; idToken: string };
  return { uid: body.localId, idToken: body.idToken };
}

/** アカウント削除で消えるべきデータ一式を書き込む */
async function seedUserData(uid: string): Promise<void> {
  const batch = firestore.batch();
  batch.set(firestore.doc(userDocumentPath(uid)), { plan: "free" });
  batch.set(firestore.collection(userSubcollectionPath(uid, userSubcollectionIds.apiTokens)).doc("token1"), {
    hash: "dummy-hash",
  });
  batch.set(firestore.collection(userSubcollectionPath(uid, userSubcollectionIds.devices)).doc("device1"), {
    deviceToken: "dummy-device-token",
  });
  batch.set(firestore.collection(userSubcollectionPath(uid, userSubcollectionIds.alarms)).doc("alarm1"), {
    title: "Deploy finished",
  });
  await batch.commit();
}

/** ユーザー配下に残っているドキュメント数 (本体 + 3 サブコレクション) */
async function remainingDocumentCount(uid: string): Promise<number> {
  const userDocument = await firestore.doc(userDocumentPath(uid)).get();
  const subcollectionCounts = await Promise.all(
    Object.values(userSubcollectionIds).map(async (subcollection) => {
      const snapshot = await firestore.collection(userSubcollectionPath(uid, subcollection)).get();
      return snapshot.size;
    })
  );
  return (userDocument.exists ? 1 : 0) + subcollectionCounts.reduce((total, count) => total + count, 0);
}

async function callDeleteAccount(idToken?: string): Promise<{ status: number; body: unknown }> {
  const response = await fetch(deleteAccountUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(idToken === undefined ? {} : { Authorization: `Bearer ${idToken}` }),
    },
    body: JSON.stringify({ data: {} }),
  });
  return { status: response.status, body: await response.json() };
}

/** sweep の対象になる、十分に古い目印の作成時刻 */
const staleRequestedAt = new Date(Date.now() - deletionMarkerMinimumAgeMs - 60_000);

describe("deleteAccount", () => {
  beforeAll(() => {
    for (const variable of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]) {
      if (process.env[variable] === undefined) {
        throw new Error(`${variable} is not set. Run this test through \`npm test\`.`);
      }
    }
  });

  afterAll(async () => {
    await deleteApp(app);
  });

  beforeEach(async () => {
    await firestore.recursiveDelete(firestore.collection(usersCollectionId));
    await firestore.recursiveDelete(firestore.collection(deletedAccountsCollectionId));
    await auth.deleteUsers((await auth.listUsers()).users.map((user) => user.uid));
  });

  it("deletes the Firestore documents and the Auth user", async () => {
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    expect(await remainingDocumentCount(uid)).toBe(4);

    const result = await deleteUserAccount(uid);

    expect(result).toEqual({ authUserExisted: true, userDocumentExisted: true });
    expect(await remainingDocumentCount(uid)).toBe(0);
    await expect(auth.getUser(uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
    // 掃除まで終わったアカウントの目印は残さない
    expect((await firestore.doc(deletedAccountDocumentPath(uid)).get()).exists).toBe(false);
  });

  it("finishes the cleanup of accounts whose deletion stopped after the Auth user was removed", async () => {
    // Auth の削除後に掃除が失敗した状態: 目印が残り、配下のデータと Auth のユーザーが残っている
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    await firestore.doc(deletedAccountDocumentPath(uid)).set({ requestedAt: staleRequestedAt });
    const untouched = await signUpAnonymously();
    await seedUserData(untouched.uid);

    // 削除が確定した (Auth のユーザーが消えている) 状態にする
    await auth.deleteUser(uid);

    const swept = await sweepDeletedAccounts(10);

    expect(swept).toEqual({ completed: 1, withdrawn: 0, failed: 0 });
    expect(await remainingDocumentCount(uid)).toBe(0);
    expect((await firestore.doc(deletedAccountDocumentPath(uid)).get()).exists).toBe(false);
    // 目印の無いアカウントには触れない
    expect(await remainingDocumentCount(untouched.uid)).toBe(4);
    expect((await auth.getUser(untouched.uid)).uid).toBe(untouched.uid);
  });

  it("withdraws the marker of an account whose Auth deletion did not complete", async () => {
    // Auth の削除前に失敗して目印だけ残った状態: ユーザーもデータもそのまま
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    await firestore.doc(deletedAccountDocumentPath(uid)).set({ requestedAt: staleRequestedAt });

    const swept = await sweepDeletedAccounts(10);

    expect(swept).toEqual({ completed: 0, withdrawn: 1, failed: 0 });
    expect(await remainingDocumentCount(uid)).toBe(4);
    expect((await auth.getUser(uid)).uid).toBe(uid);
    expect((await firestore.doc(deletedAccountDocumentPath(uid)).get()).exists).toBe(false);
  });

  it("does not remove a marker that a retry rewrote after the sweep read it", async () => {
    // 古い目印を読んだ後、Callable の再試行が目印を置き直した状態
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    const marker = firestore.doc(deletedAccountDocumentPath(uid));
    await marker.set({ requestedAt: staleRequestedAt });
    const stale = await marker.get();
    await marker.set({ requestedAt: new Date() });

    await expect(marker.delete({ lastUpdateTime: stale.updateTime })).rejects.toThrow();
    expect((await marker.get()).exists).toBe(true);
  });

  it("keeps the marker that an overlapping deletion rewrote while finishing its own", async () => {
    // 同じ uid の削除が重なり、後の呼び出しが目印を置き直した後に先の呼び出しが終わった状態
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    const marker = firestore.doc(deletedAccountDocumentPath(uid));
    const deletion = deleteUserAccount(uid);
    // deleteUserAccount が目印を置いたのを待ってから、別の呼び出しとして目印を置き直す
    for (let attempt = 0; !(await marker.get()).exists; attempt += 1) {
      if (attempt >= 200) throw new Error("deleteUserAccount did not write the marker in time");
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    await marker.set({ requestedAt: new Date() });

    await deletion;

    expect(await remainingDocumentCount(uid)).toBe(0);
    await expect(auth.getUser(uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
    // 置き直された目印は残り、sweep が後で掃除の完了を確認する
    expect((await marker.get()).exists).toBe(true);
  });

  it("leaves a fresh marker alone because its deletion may still be in progress", async () => {
    // Callable が目印を置いた直後 (Auth の削除前) に sweep が走った状態
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    await firestore.doc(deletedAccountDocumentPath(uid)).set({ requestedAt: new Date() });

    const swept = await sweepDeletedAccounts(10);

    expect(swept).toEqual({ completed: 0, withdrawn: 0, failed: 0 });
    expect((await firestore.doc(deletedAccountDocumentPath(uid)).get()).exists).toBe(true);
    expect(await remainingDocumentCount(uid)).toBe(4);
  });

  it("succeeds without changing anything when the account is already deleted", async () => {
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);
    await deleteUserAccount(uid);

    const result = await deleteUserAccount(uid);

    expect(result).toEqual({ authUserExisted: false, userDocumentExisted: false });
    expect(await remainingDocumentCount(uid)).toBe(0);
  });

  it("deletes the caller's own account through the callable endpoint", async () => {
    const { uid, idToken } = await signUpAnonymously();
    await seedUserData(uid);

    const response = await callDeleteAccount(idToken);

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      result: { userId: uid, authUserExisted: true, userDocumentExisted: true },
    });
    expect(await remainingDocumentCount(uid)).toBe(0);
    await expect(auth.getUser(uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
  });

  it("rejects an unauthenticated call and keeps the data", async () => {
    const { uid } = await signUpAnonymously();
    await seedUserData(uid);

    const response = await callDeleteAccount();

    expect(response.status).toBe(401);
    expect(response.body).toMatchObject({ error: { status: "UNAUTHENTICATED" } });
    expect(await remainingDocumentCount(uid)).toBe(4);
    expect((await auth.getUser(uid)).uid).toBe(uid);
  });
});
