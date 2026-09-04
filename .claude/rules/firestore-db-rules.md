---
paths:
  - "firebase/**"
---

# Firestore の運用ルール

DB は Firestore (`alarmify-prod`、asia-northeast1)。構成の決定は [ADR 0001](../../documents/adr/0001-firebase-backend.md)。

## スキーマ定義の置き場所

- コレクション・ドキュメントの型は `firebase/functions/src/schema/` に TypeScript の型 + zod スキーマとして定義し、Functions からもテストからもそこを参照する。コレクション名・フィールド名の文字列リテラルをコード内に散らばらせない
- 予定するコレクション: `users/{uid}` (アカウント・プラン)、`users/{uid}/apiTokens/{tokenId}` (ハッシュ化した API トークン)、`users/{uid}/devices/{deviceId}` (デバイストークン・プラットフォーム・最終確認日時)、`users/{uid}/alarms/{alarmId}` (アラーム要求と配送状態。30 日で削除)
- API トークンは平文で保存しない。SHA-256 のハッシュとプレフィックス (表示用) だけを保存し、平文は発行時に 1 度だけ返す

## クライアントからの直接アクセス

- iOS アプリは Firestore を直接読み書きしない。すべて Functions の HTTPS API を経由する (トークン検証・レート制限・プランの判定をサーバーに集約するため)。`firebase/firestore.rules` は全パス `allow read, write: if false` を維持する
- 外部サービスからの API も同じ Functions を通る。認証は Bearer トークン (API トークン) のみ

## マイグレーション

- スキーマ変更は「新フィールドを Optional で追加 → Functions が両方を読める状態でデプロイ → 既存ドキュメントの埋め戻しスクリプト (`firebase/functions/scripts/migrate-*.ts`) を 1 回実行 → 旧フィールドの参照を削除」の順で行う。埋め戻しスクリプトは冪等にする (再実行しても結果が変わらない)
- 削除系の変更 (フィールド・コレクションの削除) は埋め戻し完了後の別 PR にする

## インデックスとコスト

- 複合インデックスは `firebase/firestore.indexes.json` で管理し、Console で手作業で追加しない
- 一覧取得のクエリには必ず `limit` を付ける (履歴は 30 日で削除するが、上限なしの取得を書かない)
- 定期削除 (30 日経過したアラーム要求) は Scheduled Function で行い、1 回の実行で処理する件数に上限を設ける

## ローカル開発

- `demo-alarmify` プロジェクト ID で Firebase Emulator Suite を使う。実プロジェクトへ接続するテストを書かない
- `firebase/.firebaserc` は `default: demo-alarmify`、`prod: alarmify-prod` とし、デプロイ時は `--project prod` を明示する (`~/.claude/rules/firebase-environment-check.md`)
