# Functions の npm audit の残件と再確認条件

`firebase/functions` の `npm audit` で残っている既知脆弱性と、解消できない理由・影響範囲・再確認の条件を記録する。点検の起点は #63、対応は #67。

## 実行方法

```sh
npm --prefix firebase/functions audit            # 開発依存を含む全依存
npm --prefix firebase/functions audit --omit=dev # 本番 (Cloud Functions にデプロイされる) 依存だけ
```

本番依存 (`--omit=dev`) は検出 0 を維持する。開発依存の残件は firebase-tools (Firebase CLI) の推移依存だけで、Cloud Functions のランタイムには含まれない。

## 残件 (2026-09-12、firebase-tools 15.30.0)

いずれも firebase-tools の推移依存で、`npm audit` の fixAvailable は firebase-tools 10.1.1 へのダウングレード (破壊的) しか提示しない。npm の `overrides` で修正版へ差し替えることもできない (下記の理由)。

| パッケージ | advisory | 修正版 | firebase-tools の宣言 | 解消できない理由 | このプロジェクトでの到達可能性 |
| --- | --- | --- | --- | --- | --- |
| stream-json | https://github.com/advisories/GHSA-528h-pc64-c93x (pick / ignore / filter / replace が入れ子の深さに対して O(depth²) の DoS) | 3.5.0 | `^1.7.3` | 3.x は subpath の export 構成が変わり、`stream-json/filters/Pick` 等の require が MODULE_NOT_FOUND になる。override すると `auth:import` / `database:import` / Next.js 連携が壊れる (上流 https://github.com/firebase/firebase-tools/issues/11036 で実証済み) | 使用箇所は `auth:import`・`database:import`・Next.js framework の 3 つだけで、いずれもローカルファイルを入力にする。本プロジェクトは 3 つとも使わない |
| csv-parse | https://github.com/advisories/GHSA-8cw4-87c7-c6xx (`columns: true` + `group_columns_by_name: true` で `__proto__` ヘッダーによる prototype 置換) | 7.0.2 | `^5.0.4` | 2 メジャー先のため上流の更新待ち (同じ上流 issue 11036 で報告済み) | 使用箇所は `auth:import` の CSV 読み込みだけで、`parse()` をオプション無しで呼ぶため advisory の前提 (`columns` オプション) を満たさない。本プロジェクトは `auth:import` を使わない |
| @opentelemetry/core (経路: @google-cloud/pubsub 5.x) | https://github.com/advisories/GHSA-8988-4f7v-96qf (W3C Baggage ヘッダーの extract でサイズ上限なし) | 2.8.0 | `@google-cloud/pubsub ^5.2.0` (pubsub 6.x が core ^2.8.0 に依存) | pubsub 5 → 6 はメジャー更新 (google-gax 6・google-auth-library 11 を伴う) で、firebase-tools 側の更新待ち | 使用箇所は Pub/Sub エミュレータ (`lib/emulator/pubsubEmulator.js`) だけ。本プロジェクトのエミュレータは Firestore / Auth / Functions で Pub/Sub を起動しない |

上流の状況: firebase-tools の maintainer が https://github.com/firebase/firebase-tools/issues/11036 で「次のリリースで修正する見込み」と回答している (2026-09-10)。master (15.30.0) 時点では 3 つとも宣言範囲が未更新。

## 解消済み

- qs (https://github.com/advisories/GHSA-x5fp-wj9c-mxmx と https://github.com/advisories/GHSA-4mjr-xmp4-gh2g): firebase-tools 15.30.0 への更新と、firebase-tools 配下の body-parser を 1.20.8 (qs ~6.16.0) へ更新して解消した。express 4.22.2 だけが qs ~6.15.1 を固定しているため、`package.json` の `overrides` に `"express@4": { "qs": "^6.16.0" }` を置いている。これは semver-minor の互換更新で、express 4.x が同じ更新 (qs ~6.16.0) を 4.22.3 として準備中 ( https://github.com/expressjs/express/pull/7466 )
- `overrides` はこのリポジトリの `npm ci` にだけ効く。デプロイ workflow (`.github/workflows/functions-deploy.yml`) と `make deploy-functions` が別途インストールするグローバルの firebase-tools には効かないため、そちらの express 4 内の qs は 6.15.3 のまま。この qs はエミュレータ・ローカル HTTP サーバーの query 解析にだけ使われ、デプロイ処理では外部入力を受けない

## 再確認の条件

次のいずれかが起きたら firebase-tools を更新して `npm audit` を再実行し、この文書を更新する。

- `npm view firebase-tools dependencies` で `stream-json` が `>=3.5.0`、`csv-parse` が `>=7.0.2`、`@google-cloud/pubsub` が `>=6` になった (上流 issue 11036 の close を目安にする)
- express 4.22.3 (qs ~6.16.0) が公開され、firebase-tools がそれを解決するようになった。`overrides` の `express@4` を削除して `npm install` し、`npm ls qs --all` で 6.16.0 以上だけになることを確認する
- 残件の severity が high 以上に引き上げられた、または本プロジェクトが `auth:import` / `database:import` / Pub/Sub エミュレータを使い始めた (到達可能性の前提が崩れる)

firebase-tools を更新した時は、`Makefile` と `.github/workflows/functions-deploy.yml` の `FIREBASE_TOOLS_VERSION`、`documents/revenuecat-webhook.md` の `npx firebase-tools@<version>` を同じバージョンに揃える。
