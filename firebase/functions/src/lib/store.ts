import type { DocumentData, DocumentReference, Firestore } from "firebase-admin/firestore";
import { Timestamp } from "firebase-admin/firestore";
import { hashApiToken, hashEquals } from "./apiToken.js";
import { monthKey } from "./plan.js";
import { collections, type User } from "../schema/index.js";

/** アラーム要求の保持期間。expiresAt を過ぎたものは Scheduled Function が削除する */
export const ALARM_RETENTION_DAYS = 30;

/** 1 ユーザーが登録できる端末数の上限。配送はここまでの全端末に行う */
export const MAX_DEVICES_PER_USER = 20;

export function userRef(firestore: Firestore, uid: string): DocumentReference<DocumentData> {
  return firestore.collection(collections.users).doc(uid);
}

/** アカウント削除の目印 (`deletedAccounts/{uid}`)。存在する間はそのユーザーのデータを作り直さない */
export function deletionMarkerRef(firestore: Firestore, uid: string): DocumentReference<DocumentData> {
  return firestore.collection(collections.deletedAccounts).doc(uid);
}

export function newUserDocument(now: Date): User {
  const timestamp = Timestamp.fromDate(now);
  return {
    plan: "free",
    monthlyUsage: { month: monthKey(now), scheduledAlarmCount: 0 },
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

/** 基準時刻から保持期間が経過した時刻 */
export function expiresAfter(base: Date): Timestamp {
  return Timestamp.fromMillis(base.getTime() + ALARM_RETENTION_DAYS * 24 * 60 * 60 * 1000);
}

/**
 * 登録中のアラーム要求を削除してよくなる時刻。
 * 発火が保持期間より先のアラームでも、発火するまでは取り消せる必要があるため、発火時刻を基準に取る
 */
export function expiresAtOf(createdAt: Date, fireAt: Date): Timestamp {
  return expiresAfter(createdAt.getTime() >= fireAt.getTime() ? createdAt : fireAt);
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
export async function listDevices(firestore: Firestore, uid: string): Promise<RegisteredDevice[]> {
  const snapshot = await userRef(firestore, uid)
    .collection(collections.devices)
    .orderBy("createdAt", "asc")
    .limit(MAX_DEVICES_PER_USER)
    .get();
  return snapshot.docs.flatMap((doc) => {
    const fcmToken = doc.get("fcmToken");
    return typeof fcmToken === "string" && fcmToken.length > 0
      ? [{ deviceId: doc.id, fcmToken }]
      : [];
  });
}
