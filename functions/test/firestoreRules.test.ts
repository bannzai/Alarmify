import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import {
  assertFails,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import { afterAll, beforeAll, describe, it } from "vitest";
import { emulatorHost, PROJECT_ID } from "./helpers.js";

/** 実行時の作業ディレクトリ (functions/ かリポジトリルート) の差を吸収して firestore.rules を探す */
function findRulesPath(): string {
  let directory = process.cwd();
  for (let depth = 0; depth < 5; depth += 1) {
    const candidate = join(directory, "firestore.rules");
    if (existsSync(candidate)) {
      return candidate;
    }
    directory = dirname(directory);
  }
  throw new Error("firestore.rules が見つかりません");
}

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  const [host, port] = emulatorHost().split(":");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(findRulesPath(), "utf8"), host, port: Number(port) },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

// iOS アプリも外部サービスも Functions の HTTPS API を経由する。クライアント SDK からは一切触れない
describe("firestore.rules", () => {
  it("認証済みのクライアント SDK でも読み書きできない", async () => {
    const firestore = testEnv.authenticatedContext("test-uid").firestore();
    await assertFails(getDoc(doc(firestore, "users/test-uid")));
    await assertFails(setDoc(doc(firestore, "users/test-uid"), { plan: "pro" }));
    await assertFails(getDoc(doc(firestore, "users/test-uid/apiTokens/token-1")));
    await assertFails(getDoc(doc(firestore, "users/test-uid/alarms/alarm-1")));
  });

  it("未認証のクライアント SDK でも読み書きできない", async () => {
    const firestore = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(firestore, "users/test-uid")));
    await assertFails(setDoc(doc(firestore, "users/test-uid/devices/device-1"), { fcmToken: "x" }));
  });
});
