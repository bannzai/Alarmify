# 0006. api.signalarm.app は Cloudflare Worker で Functions へ中継する

## Status
Accepted (2026-09-12)

## Context
外部サービス向け API (`POST /v1/alarms` 等) の実体は Cloud Functions gen2 の `alarmsApi` (asia-northeast1) で、URL は `https://asia-northeast1-alarmify-prod.cloudfunctions.net/alarmsApi` と Cloud Run の `https://alarmsapi-<番号>.asia-northeast1.run.app` の 2 つがある。製品名 Signalarm のドメイン `signalarm.app` を Cloudflare Registrar で購入し、LP は Cloudflare Pages の `signalarm.app`、API は `api.signalarm.app` で公開することにした (#56)。API のホスト名は docs/・アプリ内の連携レシピ・利用者の設定 (Home Assistant や GitHub Actions の Secrets) に埋め込まれるため、一度公開したら変えにくい。

`api.signalarm.app` を `alarmsApi` へ向ける方式には次の候補があった。

1. Cloud Run のドメインマッピング (`gcloud run domain-mappings create`)
2. Firebase Hosting のサイトを作り、rewrite で Cloud Run サービスへ転送する
3. Cloud Run 向けの Global External Application Load Balancer
4. Cloudflare Worker を `api.signalarm.app` の custom domain に置き、要求をそのまま Cloud Run の URL へ中継する

1 は Google が Preview で「レイテンシの問題があり本番向けではない」と明記しており、証明書の発行に最大 24 時間かかる。さらにドメインを Google アカウントで所有確認する必要があり、`gcloud domains list-user-verified` に `signalarm.app` は無く、Search Console での確認はブラウザ操作になる。2 は GA だが、Hosting のサイトと custom domain の所有確認 (TXT) と証明書の発行を Firebase 側で待つ必要があり、DNS は Cloudflare の proxy を外した A レコードにしなければならない。Functions のデプロイとは別に Hosting のデプロイも増える。3 は固定費 (月 $18 程度から) がかかり、個人向けの Webhook API には過剰。

4 は同じ Cloudflare アカウントの同じ zone で完結し、DNS レコードと証明書は wrangler の `custom_domain = true` が用意する (同アカウントで kai8ku.com・resumemo.app の Worker custom domain として運用実績がある)。Google 側の所有確認は不要で、既存の Pages 配信と同じ API トークン・同じ GitHub Actions environment で配信できる。Functions はクライアント IP を認証やレート制限に使っていない (`externalApi.ts` は X-Forwarded-For を信用せずインスタンス単位・トークン単位で数える) ため、間に中継が入っても挙動は変わらない。

## Decision
方式 4 を採る。`scripts/api-proxy/` の Worker `signalarm-api` が `api.signalarm.app` への要求をホスト名だけ差し替えて `https://alarmsapi-<番号>.asia-northeast1.run.app` へ転送する (パス・クエリ・メソッド・ヘッダー・ボディはそのまま。cloudfunctions.net の URL は関数名がパスに付くため使わない)。認証・レート制限・レスポンスは Functions 側のままで、Worker はロジックを持たない。

- 配信: `.github/workflows/api-proxy-deploy.yml` (main への `scripts/api-proxy/**` の変更で `wrangler deploy`。PR ではテストのみ)。Pages と同じ environment `cloudflare-pages` の Secrets を使う
- 公開する入口は custom domain だけ (`workers_dev = false`、`preview_urls = false`)。Functions の直接 URL は残るが、docs/・アプリ内の連携レシピ・ストア metadata は `api.signalarm.app` だけを案内する
- アプリ側は `AlarmifyBackend.alarmsAPIBaseURL` の production を `https://api.signalarm.app` にし、連携レシピ画面が docs/ と同じホストを表示する。emulator は従来どおり Functions エミュレータの `alarmsApi` を指す

## Consequences

**良い点:**
- ドメイン・DNS・証明書・配信が Cloudflare に集約され、Google 側の所有確認や Hosting の追加デプロイが要らない。切り替えは wrangler の 1 コマンドで、数分で HTTPS が通る
- Worker が薄い中継なので、将来 Functions を別の実体 (Cloud Run の別サービス等) に移しても `ORIGIN_URL` の変更だけで公開ホストを保てる
- Cloudflare の Free プランの範囲 (1 日 10 万リクエスト) で追加費用が無い

**悪い点 / 引き受けるリスク:**
- Cloudflare のエッジから東京の Cloud Run への 1 ホップ分の遅延が加わる (Webhook の用途では問題にならない)
- 1 日 10 万リクエストを超えると Free プランでは Worker がエラーを返す。超える見込みが出たら Workers Paid ($5/月) に上げる
- API の可用性が Cloudflare と Google の両方に依存する。Cloudflare の障害時は Functions の直接 URL で回避できるが、利用者の設定は `api.signalarm.app` 固定のため案内が要る
- Worker の `ORIGIN_URL` は Cloud Run サービスの URL を直書きしている。プロジェクト番号やサービス名が変わる (プロジェクトの作り直し等) 時は wrangler.toml の更新が要る
- Cloud Run 側は誰でも到達できる公開サービスのままで、Cloudflare の WAF・レート制限は Worker を通る経路にしか効かない
