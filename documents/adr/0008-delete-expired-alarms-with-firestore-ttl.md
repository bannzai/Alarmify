# 0008. 期限切れのアラーム要求は Firestore の TTL ポリシーで削除する

## Status
Accepted (2026-09-14)

## Context
アラーム要求 (`users/{uid}/alarms/{alarmId}`) は保持期間 30 日 (`ALARM_RETENTION_DAYS`) を過ぎた時刻 `expiresAt` を持ち、公開文書 (`docs/api.md`、`docs/PrivacyPolicy-*.md`) で「30 日で自動的に削除する」と約束している。削除は Scheduled Function `cleanupExpiredAlarms` が 6 時間毎に最大 500 件 × 20 バッチ = 10,000 件を消す方式で、処理能力は 1 日 40,000 件・30 日で 120 万件だった。#62 の試算で、これが利用規模の上限 (Pro 月 1000 件なら 1,200 人相当) になり、超えると期限切れが滞留して履歴 (`GET /v1/alarms`) に残り続けることが分かった (#74)。

選択肢は 2 つあった。

1. 定数を変える (実行間隔を 30 分〜1 時間毎に短くする・バッチ数を増やす・関数の timeout を延ばす)。既存の仕組みのまま処理能力を 6〜12 倍にできるが上限は残り、期限切れ 1 件につきクエリの 1 read と Cloud Run の実行時間が掛かり続ける
2. Firestore の TTL ポリシー (`alarms` コレクショングループの `expiresAt`) に切り替える。削除は Firestore 側が行い件数の上限が無くなる。TTL の削除は無料枠の対象外で、料金は通常の削除と同じ単価 (2026-09-13 の料金ページ https://cloud.google.com/firestore/pricing で「TTL deletes」が無料枠なしの項目に挙がり、既定表示 (Iowa) の価格表で TTL Deletes の行が Document Deletes と同額 ($0.01 / 100,000 件) であることを確認。東京の TTL Deletes の行は取得したページに描画されておらず、東京の Document Deletes と同じ $0.013 / 100,000 件と仮定している)。削除は「通常は期限から 24 時間以内」の best effort で、削除されるまで期限切れがクエリに現れる (https://docs.cloud.google.com/firestore/native/docs/ttl)

2026-09-13 に #74 のコメントで両案を比較し、2026-09-14 にリポジトリ owner が TTL を選んだ (判断の記録は #74 のコメント)。

## Decision
方式 2 を採る。

- **TTL ポリシー**: `firebase/firestore.indexes.json` の `fieldOverrides` (`alarms` / `expiresAt`) に `ttl: true` を置き、`firebase deploy --only firestore --project prod` で適用する (firebase-tools が `ttlConfig` を PATCH する)。Console や `gcloud firestore fields ttls` で手作業で変えない。`expiresAt` の単一フィールド索引 (COLLECTION / COLLECTION_GROUP) は予備の経路のクエリに要るため残す。書き込みは月 1,000 万件でも平均 4 件/秒で、タイムスタンプ索引のホットスポット (500 writes/秒) には届かない
- **予備の経路**: `cleanupExpiredAlarms` は削除の主経路ではなくなり、TTL の猶予 `CLEANUP_TTL_GRACE_HOURS` (48 時間 = ドキュメントの「24 時間以内」の 2 倍) を過ぎても残っている期限切れだけを削除する。1 日 1 回に減らし (猶予より細かく回しても消し残しは増えない)、1 回の上限 (500 件 × 20 バッチ) と「問い合わせ後に更新された文書は消さない」保護はそのまま残す
- **滞留の検知**: 予備の経路が 1 件でも削除したら error ログ `expired alarms outlived the TTL policy` を出し、そのメッセージに一致するログ条件のアラートポリシー (`firebase/monitoring/expired-alarms-outlived-ttl.policy.json`。通知先は既存の Slack `#alarmify-notification` + メール) で通知する。既存の `error-log-spike` は「5 分間に 10 件超」が条件で 1 行の error では発火しないため、別に持つ。ポリシーは `firebase/monitoring/apply-policy.sh` で冪等に適用する
- **処理能力の根拠** (`documents/cost.md`「費用の上限」): TTL には件数の上限が無く、月 300 万件 (旧プランの Pro 10,000 人 / 新プランの Pro 3,000 人相当) でも 1 日 10 万件を Firestore 側が消す。費用は $0.013 × 30 = 約 $0.39 / 月 (無料枠なし)。旧方式の同規模の費用 (クエリの read 約 $1.14 + Cloud Run 約 $0.2 + 削除 約 $0.31) より安い
- **ルールの更新**: `.claude/rules/firestore-db-rules.md` の「定期削除は Scheduled Function で行う」を、TTL ポリシーを主経路・Scheduled Function を予備の経路とする記述に改める

## Consequences

**良い点:**
- 削除の件数に上限が無くなり、利用規模が増えても `cleanupExpiredAlarms` の増強が要らない
- 期限切れ 1 件あたりのクエリの read と Cloud Run の実行時間が消え、定期実行は 1 日 1 回の空クエリ (1 read) だけになる
- TTL の不調 (ポリシーの無効化・大量の消し残し) を予備の経路が翌日には削除し、アラートで気づける

**悪い点 / 引き受けるリスク:**
- 削除は best effort で、期限から最長 24 時間程度 (予備の経路まで含めて最長 48 時間 + 1 日) 遅れる。履歴 `GET /v1/alarms` は `expiresAt` を条件にしていないため、その間は期限切れが履歴に残る。公開文書の「30 日で削除」は実態として「30 日 + 最長 1〜2 日」になる。履歴から期限切れを隠したくなったら応答側で `expiresAt` 経過分を除く
- TTL の削除は Firestore の無料枠 (削除 20,000 件/日) の対象外。今の規模 (期限切れ 0 件/日) では差は無く、月 300 万件で約 $0.39 / 月。アラートポリシーは 2027-09-01 から $0.35 / 月 (`firebase/monitoring/README.md`)
- TTL は `expiresAt` の現在値で判定する (再スケジュールで `expiresAt` が延びた文書は消えない前提)。Firestore 側の挙動であり、旧方式の `lastUpdateTime` 条件のような自前の保護は掛けられない
- TTL の削除は Firestore トリガーを起こす。現在トリガー関数は無いため影響は無いが、`alarms` に onDocumentDeleted 等を足す時は TTL 由来の削除でも動くことを前提にする
- ポリシーの有効化に 10 分以上かかり、適用直後の本番では既存の期限切れ (2026-09-13 時点で 0 件) が一括削除の対象になる
