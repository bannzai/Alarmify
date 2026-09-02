import { readFileSync } from "node:fs";
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { deleteUserAccount } from "../src/account/deleteAccount";
import {
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
