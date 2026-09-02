import { Timestamp } from "firebase-admin/firestore";

/**
 * 一覧の続きを示すカーソル。
 * ドキュメント id だけだと、そのドキュメントが削除された時に続きを辿れなくなるため、
 * 並び順に使う値 (作成時刻) も一緒に持たせる
 */
export interface ListCursor {
  createdAt: Timestamp;
  id: string;
}

export function encodeCursor({ createdAt, id }: ListCursor): string {
  return Buffer.from(`${createdAt.toMillis()}:${id}`, "utf8").toString("base64url");
}

export function decodeCursor(cursor: string): ListCursor | null {
  const decoded = Buffer.from(cursor, "base64url").toString("utf8");
  const separator = decoded.indexOf(":");
  if (separator <= 0) {
    return null;
  }
  const millis = Number(decoded.slice(0, separator));
  const id = decoded.slice(separator + 1);
  if (!Number.isSafeInteger(millis) || id.length === 0) {
    return null;
  }
  // Firestore の Timestamp の範囲 (西暦 1 年〜9999 年) を外れる値は生成時に例外になるため、400 に落とす
  try {
    return { createdAt: Timestamp.fromMillis(millis), id };
  } catch {
    return null;
  }
}
