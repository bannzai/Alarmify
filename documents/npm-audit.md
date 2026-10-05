# Functions の npm audit の残件と再確認条件

`firebase/functions` の `npm audit` で残っている既知脆弱性と、解消できない理由・影響範囲・再確認の条件を記録する。点検の起点は #63、対応は #67 と #85。

## 実行方法

```sh
npm --prefix firebase/functions audit            # 開発依存を含む全依存
npm --prefix firebase/functions audit --omit=dev # 本番 (Cloud Functions にデプロイされる) 依存だけ
```

本番依存 (`--omit=dev`) は検出 0 を維持する。開発依存の残件は firebase-tools (Firebase CLI) の推移依存だけで、Cloud Functions のランタイムには含まれない。

## 残件 (2026-10-05、firebase-tools 15.32.1)

いずれも firebase-tools の推移依存で、`npm audit` の fixAvailable は firebase-tools 14.23.0 へのダウングレード (破壊的) しか提示しない。修正版は依存元の宣言範囲の外 (メジャー違い) にあるか存在しないため、npm の `overrides` で差し替えると依存元の CLI 機能を壊すおそれがある。上流の宣言範囲が更新されるまで override しない。

| パッケージ | advisory | 修正版 | 依存元の宣言 | このプロジェクトでの到達可能性 |
| --- | --- | --- | --- | --- |
| @opentelemetry/core (経路: @google-cloud/pubsub 5.x) | https://github.com/advisories/GHSA-8988-4f7v-96qf (W3C Baggage ヘッダーの extract でサイズ上限なし) | 2.8.0 | firebase-tools が `@google-cloud/pubsub ^5.2.0`、pubsub 5.3.1 (5.x の最新) が `@opentelemetry/core ^1.30.1`。core 2.x に依存するのは pubsub 6.x で、メジャー更新 (google-gax 6・google-auth-library 11 を伴う) | 使用箇所は Pub/Sub エミュレータ (`lib/emulator/pubsubEmulator.js`) だけ。本プロジェクトのエミュレータは Firestore / Auth / Functions で Pub/Sub を起動しない |
| basic-ftp (経路: proxy-agent → pac-proxy-agent → get-uri) | https://github.com/advisories/GHSA-c475-qrg2-pj4r (FTP のディレクトリ一覧の解析が二乗時間の DoS) | 6.2.1 | get-uri 6.0.5 / 8.0.1 (最新) とも `basic-ftp ^5.3.1` | firebase-tools 15.32.1 の `lib` は `proxy-agent` を require しない (プロキシは `apiv2.js` が undici の `ProxyAgent` で扱う)。node_modules 全体でも `proxy-agent` を読み込むコードは無く、到達しない |
| braces (経路: chokidar 3.x) | https://github.com/advisories/GHSA-vfj7-8cjw-p6xm (深く入れ子にしたパターンでスタック枯渇の DoS) | なし (3.0.3 以下すべてが対象) | firebase-tools が `chokidar ^3.6.0`。braces に依存しない chokidar 4.x はメジャー違い | 使用箇所はエミュレータのファイル監視 (Firestore / Database / Storage のルールファイルと Functions のソース) で、監視対象は `firebase.json` と functions ディレクトリのローカルパス。外部入力のパターンを受けない |

上流の状況: stream-json と csv-parse は https://github.com/firebase/firebase-tools/issues/11036 の修正 (2026-09-23 close) を含む 15.32.1 で解消した。@google-cloud/pubsub と chokidar の宣言範囲は 15.32.1 でも未更新。

## グローバル導入の Firebase CLI

デプロイ workflow (`.github/workflows/functions-deploy.yml`) と `make deploy-functions` はプロジェクトの `node_modules` ではなく、`FIREBASE_TOOLS_VERSION` の firebase-tools を別途インストールして使う。そちらには `package.json` の `overrides` も `package-lock.json` も効かず、インストール時点の最新の解決になる。

firebase-tools 15.32.1 を単独でインストールした `npm audit` (2026-10-05) では、上記の残件に加えて次が出る。

| パッケージ | advisory | プロジェクト側の対処 | デプロイでの到達可能性 |
| --- | --- | --- | --- |
| re2 1.24.1 (経路: superstatic) | https://github.com/advisories/GHSA-6hxr-mr5r-9836 ほか 3 件 (空文字にマッチするパターンの `String.prototype.match` で無限ループ等) | `overrides` の `re2: ^1.26.1` | 使用箇所は superstatic (Hosting のローカル配信) の URL パターン照合で、Functions のデプロイでは読み込まない |
| uuid 9.0.1 (経路: gaxios 6.7.1) | https://github.com/advisories/GHSA-w5hq-g745-h8pq (v3 / v5 / v6 に `buf` を渡した時の境界検査漏れ) | `overrides` の `gaxios` → `uuid: ^11.1.1` | gaxios 6 は multipart の boundary 生成に `v4()` だけを使い、advisory の前提 (v3 / v5 / v6 と `buf`) を満たさない |

qs は express 4.22.3 (qs ~6.16.0) の公開で、グローバル導入でも 6.16.0 に解決される。

## 解消済み

- stream-json (https://github.com/advisories/GHSA-528h-pc64-c93x) と csv-parse (https://github.com/advisories/GHSA-8cw4-87c7-c6xx): firebase-tools 15.32.1 が `stream-json ^3.6.0`・`csv-parse ^7.0.2` を宣言したため、更新で解消した (stream-json 3.7.0・csv-parse 7.0.3)
- qs (https://github.com/advisories/GHSA-x5fp-wj9c-mxmx と https://github.com/advisories/GHSA-4mjr-xmp4-gh2g): firebase-tools 15.30.0 への更新と body-parser 1.20.8 で解消し、express 4 だけを `overrides` の `"express@4": { "qs": "^6.16.0" }` で補っていた。express 4.22.3 が qs ~6.16.0 を宣言したため override を削除し、firebase-tools 配下の express を 4.22.3 へ更新した (`npm ls qs --all` は 6.16.0 だけ)
- brace-expansion (https://github.com/advisories/GHSA-q2hr-2g5m-vwhr ほか 2 件。本番依存の firebase-admin → google-gax → rimraf → glob → minimatch の経路を含む)・hono・ip-address・morgan: 依存元の宣言範囲内の修正版へ `npm audit fix` (`--force` なし) で lockfile を更新して解消した

## 再確認の条件

次のいずれかが起きたら firebase-tools を更新して `npm audit` を再実行し、この文書を更新する。

- `npm view firebase-tools dependencies` で `@google-cloud/pubsub` が `>=6`、または `chokidar` が `>=4` になった
- get-uri (proxy-agent の経路) が `basic-ftp >=6.2.1` を宣言した、または firebase-tools が `proxy-agent` を依存から外した
- 残件の severity が critical に引き上げられた、または本プロジェクトが Pub/Sub エミュレータ・プロキシ自動設定 (PAC) を使い始めた (到達可能性の前提が崩れる)

firebase-tools を更新した時は、`Makefile` と `.github/workflows/functions-deploy.yml` の `FIREBASE_TOOLS_VERSION`、`documents/revenuecat-webhook.md` と `documents/budget-alert-slack.md` の `npx firebase-tools@<version>`、`documents/functions-deploy.md` の「workflow は <version> を固定」を同じバージョンに揃える。

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-85
claude --resume 20ae5a11-2671-4fdd-8099-c56650d89565
```
