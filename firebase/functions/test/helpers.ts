import type { Server } from "node:http";
import { once } from "node:events";
import type { Express } from "express";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import type { Message } from "firebase-admin/messaging";
import type { AppCheckEnforcementMode } from "../src/lib/appCheck.js";
import type { Deps } from "../src/lib/deps.js";

/** ローカルは demo-alarmify のエミュレータで動かす (.claude/rules/firestore-db-rules.md) */
export const PROJECT_ID = "demo-alarmify";
export const TEST_NOW = new Date("2026-09-02T00:00:00Z");
export const VALID_ID_TOKEN = "valid-id-token";
export const VALID_APP_CHECK_TOKEN = "valid-app-check-token";

export function emulatorHost(): string {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) {
    throw new Error("FIRESTORE_EMULATOR_HOST が未設定です。npm test から実行してください");
  }
  return host;
}

export function testFirestore(): Firestore {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID });
  }
  return getFirestore();
}

/** テスト間で状態を持ち越さないよう、エミュレータの全ドキュメントを消す */
export async function clearFirestore(): Promise<void> {
  const url = `http://${emulatorHost()}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
  const response = await fetch(url, { method: "DELETE" });
  if (!response.ok) {
    throw new Error(`Firestore エミュレータの初期化に失敗しました: ${response.status}`);
  }
}

export interface TestContext {
  deps: Deps;
  uid: string;
  /** sendPush が受け取ったメッセージ (呼び出しごとの配列) */
  sentBatches: Message[][];
  setNow(date: Date): void;
  setAppCheckEnforcementMode(mode: AppCheckEnforcementMode): void;
  failNextPush(): void;
  throwNextPush(): void;
}

/**
 * 既定を enforce にするのは、本番の最終形 (App Check の強制適用) で全フローが通ることを常に検証するため。
 * monitor の挙動を確かめるテストだけが setAppCheckEnforcementMode で切り替える
 */
export function createTestContext(uid = "test-uid"): TestContext {
  let now = TEST_NOW;
  let appCheckEnforcementMode: AppCheckEnforcementMode = "enforce";
  let failNext = false;
  let throwNext = false;
  const sentBatches: Message[][] = [];
  const deps: Deps = {
    firestore: testFirestore(),
    sendPush: async (messages) => {
      sentBatches.push(messages);
      if (throwNext) {
        throwNext = false;
        throw new Error("fcm unavailable");
      }
      if (failNext) {
        failNext = false;
        return { successCount: 0, failureCount: messages.length, errors: ["messaging/invalid-registration-token"] };
      }
      return { successCount: messages.length, failureCount: 0, errors: [] };
    },
    verifyIdToken: async (idToken) => {
      if (idToken !== VALID_ID_TOKEN) {
        throw new Error("invalid id token");
      }
      return { uid };
    },
    verifyAppCheckToken: async (appCheckToken) => {
      if (appCheckToken !== VALID_APP_CHECK_TOKEN) {
        throw new Error("invalid app check token");
      }
      return { appId: "1:320409781062:ios:test" };
    },
    appCheckEnforcementMode: () => appCheckEnforcementMode,
    pushDeliveryMode: () => "notification-service",
    now: () => now,
  };
  return {
    deps,
    uid,
    sentBatches,
    setNow: (date) => {
      now = date;
    },
    setAppCheckEnforcementMode: (mode) => {
      appCheckEnforcementMode = mode;
    },
    failNextPush: () => {
      failNext = true;
    },
    throwNextPush: () => {
      throwNext = true;
    },
  };
}

/**
 * テスト用の HTTP サーバーを 127.0.0.1 に束ねて起動する。
 * supertest の既定 (ポート 0 で待ち受け、127.0.0.1 へ接続) では待ち受けが `::` になり、
 * 同じ番号の IPv4 ポートを別のプロセスが持っていると、そちらへリクエストが飛んでしまう
 */
export async function startTestServer(app: Express): Promise<Server> {
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  return server;
}

export async function stopTestServer(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
