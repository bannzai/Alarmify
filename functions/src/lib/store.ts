import type {
  DocumentReference,
  DocumentData,
  Firestore,
} from "firebase-admin/firestore";
import { Timestamp } from "firebase-admin/firestore";
import { hashApiToken, hashEquals } from "./apiToken.js";
import { monthKey } from "./plan.js";
import { collections, userSchema, type User } from "../schema/index.js";

/** アラーム要求の保持期間。expiresAt を過ぎたものは Scheduled Function が削除する */
export const ALARM_RETENTION_DAYS = 30;

export function userRef(firestore: Firestore, uid: string): DocumentReference<DocumentData> {
  return firestore.collection(collections.users).doc(uid);
}

export function expiresAtOf(createdAt: Date): Timestamp {
  return Timestamp.fromMillis(createdAt.getTime() + ALARM_RETENTION_DAYS * 24 * 60 * 60 * 1000);
}

/** users/{uid} を作る。既にあれば何もしない (冪等) */
export async function ensureUser(firestore: Firestore, uid: string, now: Date): Promise<User> {
  const ref = userRef(firestore, uid);
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      return userSchema.parse(snapshot.data());
    }
    const timestamp = Timestamp.fromDate(now);
    const user: User = {
      plan: "free",
      monthlyUsage: { month: monthKey(now), scheduledAlarmCount: 0 },
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    transaction.set(ref, user);
    return user;
  });
}

export interface ResolvedApiToken {
  uid: string;
  tokenId: string;
}

/**
 * 平文の API トークンから所有者を引く。
 * 保存しているのは SHA-256 のハッシュだけなので、ハッシュの一致で照合する
 */
export async function findUserByApiToken(
  firestore: Firestore,
  plainToken: string,
): Promise<ResolvedApiToken | null> {
  const hash = hashApiToken(plainToken);
  const snapshot = await firestore
    .collectionGroup(collections.apiTokens)
    .where("hash", "==", hash)
    .limit(2)
    .get();
  for (const doc of snapshot.docs) {
    const storedHash = doc.get("hash");
    if (typeof storedHash !== "string" || !hashEquals(storedHash, hash)) {
      continue;
    }
    if (doc.get("revokedAt") !== null) {
      continue;
    }
    const uid = doc.ref.parent.parent?.id;
    if (!uid) {
      continue;
    }
    return { uid, tokenId: doc.id };
  }
  return null;
}

export interface RegisteredDevice {
  deviceId: string;
  fcmToken: string;
}

/** 一覧取得には必ず limit を付ける (.claude/rules/firestore-db-rules.md) */
export const MAX_DEVICES_PER_USER = 20;

export async function listDevices(firestore: Firestore, uid: string): Promise<RegisteredDevice[]> {
  const snapshot = await userRef(firestore, uid)
    .collection(collections.devices)
    .limit(MAX_DEVICES_PER_USER)
    .get();
  return snapshot.docs.flatMap((doc) => {
    const fcmToken = doc.get("fcmToken");
    return typeof fcmToken === "string" && fcmToken.length > 0
      ? [{ deviceId: doc.id, fcmToken }]
      : [];
  });
}
