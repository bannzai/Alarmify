# 運用費用の試算

Signalarm (Alarmify) の運用にかかる費用を、固定費・ユーザー数に比例する変動費・費用が跳ねる経路の上限に分けて試算する。起票元: https://github.com/bannzai/Alarmify/issues/62

## 前提

- 単価の参照日: 2026-09-12。各費目の出典は「単価」の表に書く。単価は変わるため、試算を使う時は出典を見直す
- 為替: 1 USD = 150 JPY の仮定。Google Cloud の請求は課金アカウントの通貨 (JPY) の SKU 単価で行われるため、USD 単価 × 為替は近似。140 / 160 JPY で ±7% ずれる
- リージョン: Firestore・Cloud Run (Cloud Functions gen2) とも `asia-northeast1` (東京)。Firestore は Standard edition の `(default)` データベース (無料枠の対象。`gcloud firestore databases list --project=alarmify-prod` で `FREE_TIER: True` を確認)
- Cloud Run の課金方式: request-based (既定)。`gcloud run services list --format=yaml` に `run.googleapis.com/cpu-throttling` が無いことで確認。最小インスタンス 0 (`minScale` の指定なし)、最大インスタンスは revision 10 (`autoscaling.knative.dev/maxScale`) / service 20 (`run.googleapis.com/maxScale`)、1 vCPU・256 MiB・同時実行 80
- 利用量の仮定 (issue #62 の条件): 無料ユーザーは月 20 アラーム (プランの上限)、Pro ユーザーは月 300 アラーム (試算上の仮定。Pro に強制上限は無い)。ユーザーあたりの登録端末数 D は既定 1 台 (上限 20 台の場合を「費用の上限」で別に示す)
- 1 HTTP リクエストあたりの Cloud Run 課金時間 t: 既定 1.0 秒 (悲観側の上限) と 0.2 秒 (暖機済み) の 2 通りで示す。根拠は本番の直近 7 日の実測 (2026-09-05〜09-12、Monitoring API の `run.googleapis.com/container/billable_instance_time` と `request_count`): `appapi` 83.5 秒 / 60 リクエスト ≈ 1.4 秒、`alarmsapi` 4.3 秒 / 5 リクエスト ≈ 0.86 秒。トラフィックがほぼ無い状態のためコールドスタートが支配的で、request-based 課金は「インスタンスが 1 つ以上のリクエストを処理している時間」に対して課金され同時実行 80 のリクエストは時間を共有するため、利用が増えるほど 1 リクエストあたりの課金時間は 0.2 秒側へ下がる
- 対象コードは main の最新 (`firebase/functions/`)。本番は 2026-09-03 デプロイの revision 00001 のままで `revenueCatWebhook` が無く、反映結果の報告 API も未反映 (#58)。試算はデプロイ後の運用を前提にする

## 単価

| 費目 | 単価 (USD) | 無料枠 | 出典 |
| --- | --- | --- | --- |
| Firestore 読み取り (東京) | $0.038 / 100,000 件 | 50,000 件/日 (プロジェクトの default DB のみ、太平洋時間で日次リセット) | https://cloud.google.com/firestore/pricing (地域を Tokyo に切り替えた表) |
| Firestore 書き込み (東京) | $0.115 / 100,000 件 | 20,000 件/日 | 同上 |
| Firestore 削除 (東京) | $0.013 / 100,000 件 | 20,000 件/日 | 同上 |
| Firestore 保存データ (東京) | $0.115 / GiB・月 | 1 GiB | 同上 |
| Cloud Run CPU (東京 = Tier 1、request-based、処理中) | $0.000024 / vCPU 秒 | 180,000 vCPU 秒/月 (課金アカウント単位) | https://cloud.google.com/run/pricing |
| Cloud Run メモリ (同上) | $0.0000025 / GiB 秒 | 360,000 GiB 秒/月 (課金アカウント単位) | 同上 |
| Cloud Run リクエスト | $0.40 / 100 万件 | 200 万件/月 (課金アカウント単位) | 同上 |
| Cloud Run 最小インスタンスのアイドル時間 | $0.0000025 / vCPU 秒 | 使わない (最小 0) | 同上 |
| Cloud Scheduler | $0.10 / ジョブ・月 | 3 ジョブ/月 (課金アカウント単位) | https://cloud.google.com/scheduler/pricing |
| Secret Manager | $0.06 / 有効なシークレットバージョン・月、アクセス $0.03 / 10,000 回 | 6 バージョン、10,000 回/月 (課金アカウント単位) | https://cloud.google.com/secret-manager/pricing |
| Cloud Logging 取り込み | $0.50 / GiB (30 日の保持込み) | 50 GiB/プロジェクト・月 | https://cloud.google.com/products/observability/pricing |
| Cloud Logging 保持 (30 日超) | $0.01 / GiB・月 | 既定の保持期間内は無料 | 同上 |
| Cloud Monitoring アラートポリシー | $0.35 / メトリック参照・月 + $0.50 / 100 万ポイント (2027-09-01 から) | なし | 同上 |
| Cloud Build (Functions のデプロイ) | $0.006 / 分 (e2-standard-2) | 2,500 分/月 (課金アカウント単位) | https://cloud.google.com/build/pricing |
| Artifact Registry (Functions のコンテナイメージ) | $0.10 / GiB・月 | 0.5 GiB (課金アカウント単位) | https://cloud.google.com/artifact-registry/pricing |
| FCM / App Check / Firebase Auth (匿名) | 無料 (Auth は 50K MAU まで。超えると Google Cloud の Identity Platform 料金) | | https://firebase.google.com/pricing |
| Apple Developer Program | $99 / 年 | | https://developer.apple.com/programs/enroll/ |
| App Store 手数料 | 売上の 15% (Small Business Program 加入時。未加入は 30%) | | https://developer.apple.com/app-store/small-business-program/ |
| RevenueCat | 月間トラッキング収益 (MTR) $2,500 まで無料。超えた月は MTR 全体の 1% (超過分だけではない) | | https://www.revenuecat.com/pricing |
| ドメイン signalarm.app | 約 $14 / 年 (issue #62 の見積。Cloudflare Registrar は原価販売で固定単価は未公開) | | https://www.cloudflare.com/application-services/products/registrar/buy-app-domains/ |
| Cloudflare Pages (LP。#56 で GitHub Pages から移行予定) | 無料 (Free プラン: 500 ビルド/月、20,000 ファイル/サイト) | | https://developers.cloudflare.com/pages/platform/limits/ |
| GitHub Actions | 無料 (public リポジトリの標準 GitHub-hosted runner。macOS を含む。larger runner は有料) | | https://docs.github.com/en/billing/managing-billing-for-your-products/about-billing-for-github-actions |

課金アカウント単位の無料枠 (Cloud Run・Scheduler・Secret Manager・Cloud Build・Artifact Registry) は、同じ課金アカウントの他の 22 プロジェクトと共有する。Scheduler の無料 3 ジョブは別プロジェクトが既に消費している (例: `aisiteru-prod` に 15 ジョブ) ため、Alarmify の 2 ジョブは有料として数える。Cloud Run の無料枠も同様に「使えれば」の扱いにし、下記の試算は無料枠の適用前 (gross) を主とする。

## 固定費 (年額)

| 費目 | 年額 |
| --- | --- |
| Apple Developer Program | $99 (¥14,850) |
| ドメイン signalarm.app | 約 $14 (¥2,100) |
| Cloud Scheduler 2 ジョブ (`cleanupExpiredAlarms` 6 時間毎、`sweepDeletedAccountsHourly` 1 時間毎) | $2.40 (¥360) |
| 定期実行そのものの Cloud Run 時間 (実測: cleanup 約 3.0 秒 × 120 回/月、sweep 約 2.8 秒 × 720 回/月 ≈ 2,376 vCPU 秒/月) | 約 $0.70 (¥105) |
| 定期削除の空クエリ (対象 0 件でも 1 read × 4 回/日) | $0.0005 (¥0.07) |
| Secret Manager (`REVENUECAT_WEBHOOK_AUTHORIZATION` 1 バージョン) | 無料枠 6 バージョン内なら $0。他プロジェクトが枠を使い切っていれば $0.72 |
| Cloud Monitoring `error-log-spike` ポリシー (メトリック参照 1 件) | 2027-09-01 から $4.20 (¥630)。それまで $0 |
| Cloud Logging・FCM・App Check・Auth・Cloudflare Pages・GitHub Actions | $0 |
| 合計 | 約 $116 (約 ¥17,400)。2027-09 以降は約 ¥18,000 |

Functions のデプロイごとの Cloud Build (数分) と Artifact Registry のイメージ保存 (`gcf-artifacts` リポジトリ。2026-09-12 時点 0 MB、cleanup policy 未設定) は無料枠内で $0 とみなす。デプロイを繰り返してイメージが溜まると Artifact Registry の保存料が乗るため、`firebase functions:artifacts:setpolicy` (Firebase CLI 14 以降の既定: 1 日より古いイメージを削除) の設定を検討する。

## 変動費: 1 アラームあたりの操作回数

登録 → 端末の反映結果の報告 → 30 日後の定期削除、というライフサイクル 1 周分。`firebase/functions/src/api/externalApi.ts`・`api/appApi.ts`・`lib/cleanup.ts` の処理をそのまま数えた (再試行・トランザクションの競合なしの正常経路)。

| 処理 | Firestore 読み取り | 書き込み | 削除 | Cloud Run リクエスト | push |
| --- | --- | --- | --- | --- | --- |
| `POST /v1/alarms` (新規登録): トークン検索 1、`lastUsedAt` 更新、端末一覧 D、トランザクション (user + alarm) 2 read / 2 write、配送前後の状態読み直し 2、配送結果の記録 1 | D + 5 | 4 | 0 | 1 | D 件 (FCM、無料) |
| `POST /v1/alarms/{id}/device-reports` (端末 1 台につき 1 回): 削除目印・アラーム・端末の 3 read、報告の 1 write | 3D | D | 0 | D | |
| `cleanupExpiredAlarms` (期限切れ 1 件につき): クエリ結果 1 read、`BulkWriter.delete` 1 | 1 | 0 | 1 | 0 | |
| 合計 | 4D + 6 | 4 + D | 1 | 1 + D | D |
| D = 1 | 10 | 5 | 1 | 2 | 1 |
| D = 20 (上限) | 86 | 24 | 1 | 21 | 20 |

このほか、アラーム文書 (deviceReports 込み) の保存を 1 件 2 KiB × 約 1 か月と置く (発火から 30 日、または取り消しから 30 日で削除)。

1 アラームあたりの費用 (D = 1):

| t (Cloud Run 課金時間 / リクエスト) | Firestore | Cloud Run | 保存 | 合計 |
| --- | --- | --- | --- | --- |
| 1.0 秒 | $0.0000097 | $0.0000501 | $0.0000002 | $0.000060 (¥0.009) |
| 0.2 秒 | $0.0000097 | $0.0000107 | $0.0000002 | $0.000021 (¥0.003) |

ユーザー 1 人あたりの月額 (D = 1):

| ユーザー | t = 1.0 秒 | t = 0.2 秒 |
| --- | --- | --- |
| 無料 (月 20 件) | $0.0012 (¥0.18) | $0.0004 (¥0.06) |
| Pro (月 300 件) | $0.018 (¥2.70) | $0.006 (¥0.92) |

登録以外の操作 (取り消し `DELETE /v1/alarms/{id}`: 読み取り D + 4、書き込み 3、push D 件。同じ内容の再送: 月間上限は消費しないが push と配送結果の記録は毎回行う。端末登録・API トークン発行・履歴取得・RevenueCat webhook・アカウント削除) は 1 ユーザーあたり月に数回のオーダーで、上の 1 アラームあたりの費用の数回分にしかならないため個別には計上しない。

## ユーザー数別の月額試算

D = 1、無料ユーザー 20 件/月、Pro 300 件/月。固定費のうち月次で乗るもの (Scheduler $0.20、定期実行の Cloud Run 時間) を含む。「無料枠適用後」は Firestore の日次無料枠 (プロジェクト単位) と Cloud Run の無料枠 (課金アカウント単位。他プロジェクトが使っていなければ) を全額この用途に充てた場合。

t = 1.0 秒 (上限側):

| ユーザー数 | Pro 比率 | 月間アラーム | Firestore | Cloud Run | 合計 (無料枠適用前) | 無料枠適用後 |
| --- | --- | --- | --- | --- | --- | --- |
| 100 | 0% | 2,000 | $0.02 | $0.16 | $0.38 (¥57) | $0.20 (¥30) |
| 100 | 5% | 3,400 | $0.03 | $0.23 | $0.46 (¥69) | $0.20 (¥30) |
| 100 | 100% | 30,000 | $0.30 | $1.56 | $2.06 (¥309) | $0.20 (¥30) |
| 1,000 | 0% | 20,000 | $0.20 | $1.06 | $1.46 (¥219) | $0.20 (¥30) |
| 1,000 | 5% | 34,000 | $0.34 | $1.76 | $2.30 (¥345) | $0.20 (¥30) |
| 1,000 | 100% | 300,000 | $2.97 | $15.07 | $18.24 (¥2,737) | $11.94 (¥1,791) |
| 10,000 | 0% | 200,000 | $1.98 | $10.07 | $12.25 (¥1,837) | $6.19 (¥928) |
| 10,000 | 5% | 340,000 | $3.37 | $17.08 | $20.64 (¥3,096) | $14.24 (¥2,137) |
| 10,000 | 100% | 3,000,000 | $29.70 | $150.21 | $180.11 (¥27,016) | $172.63 (¥25,895) |

t = 0.2 秒 (暖機済み):

| ユーザー数 | Pro 比率 | 月間アラーム | Firestore | Cloud Run | 合計 (無料枠適用前) | 無料枠適用後 |
| --- | --- | --- | --- | --- | --- | --- |
| 100 | 0% | 2,000 | $0.02 | $0.08 | $0.30 (¥45) | $0.20 (¥30) |
| 100 | 5% | 3,400 | $0.03 | $0.09 | $0.33 (¥49) | $0.20 (¥30) |
| 100 | 100% | 30,000 | $0.30 | $0.38 | $0.88 (¥131) | $0.20 (¥30) |
| 1,000 | 0% | 20,000 | $0.20 | $0.27 | $0.67 (¥100) | $0.20 (¥30) |
| 1,000 | 5% | 34,000 | $0.34 | $0.42 | $0.96 (¥144) | $0.20 (¥30) |
| 1,000 | 100% | 300,000 | $2.97 | $3.25 | $6.42 (¥964) | $1.81 (¥271) |
| 10,000 | 0% | 200,000 | $1.98 | $2.19 | $4.37 (¥655) | $0.85 (¥128) |
| 10,000 | 5% | 340,000 | $3.37 | $3.68 | $7.25 (¥1,087) | $2.19 (¥328) |
| 10,000 | 100% | 3,000,000 | $29.70 | $32.01 | $61.91 (¥9,286) | $54.58 (¥8,187) |

読み方:

- 10,000 ユーザーまでは Cloud Run の CPU 時間が支配的で、Firestore は 1/5 以下。CPU 時間の仮定 (1.0 秒か 0.2 秒か) で合計が約 3〜5 倍変わる。実利用が増えたら `billable_instance_time / request_count` を測り直して t を更新する
- 無料ユーザーだけなら 10,000 人でも月 ¥2,000 以下、Pro 5% の混合でも月 ¥3,100 以下 (t = 1.0 秒)。月 ¥10,000 の予算 (下記) を超えるのは 10,000 人が全員 Pro 300 件/月の場合だけ
- 月間 300 万アラーム (10,000 人 × Pro) では定期削除の処理能力 (下記「費用の上限」の定期削除) を超えるため、その規模の前に `cleanupExpiredAlarms` の増強が要る

## 損益分岐 (Pro 年 ¥2,300)

- 固定費 年額 約 ¥17,400 (上表。Apple $99 + ドメイン $14 + GCP の基礎分 $3.10)
- Pro 1 人の手取り: App Store の日本の価格 ¥2,300 は消費税 10% 込みで、Apple は税抜 (¥2,091) から手数料を引く。Small Business Program 加入 (15%) なら ¥1,777 / 年、未加入 (30%) なら ¥1,464 / 年。加入状況は未確認 (加入は App Store Connect での申請が要る)
- Pro 1 人の変動費: ¥32 / 年 (t = 1.0 秒、300 件/月)。無料 1 人の変動費: ¥2.2 / 年
- RevenueCat: MTR が月 $2,500 (約 ¥375,000。年額 ¥2,300 の購入が同じ月に 163 件) を超える月だけ MTR 全体の 1% (その月の売上の 1%)。年額課金は購入月に売上が集中するため、更新月が偏ると早く超える

| 手数料 | Pro 1 人の粗利 (手取り − 変動費) | 損益分岐 (Pro だけ) | 損益分岐 (Pro 比率 5%。Pro 1 人につき無料 19 人の変動費を負担) |
| --- | --- | --- | --- |
| 15% | ¥1,745 / 年 | Pro 10 人 | Pro 11 人 = 全体 204 人 |
| 30% | ¥1,432 / 年 | Pro 13 人 | Pro 13 人 = 全体 251 人 |

年間 Pro 10〜13 人で固定費を回収でき、それ以降は Pro 1 人あたり年 ¥1,400〜1,750 が残る。変動費は手取りの 2% 程度で、損益をほぼ動かさない。

## 費用の上限: 何がどこで止まり、何は止まらないか

費用が跳ねる経路 (API トークンの漏洩による大量登録、無限ループする外部サービス) に対して、コードに入っている上限とその効き方。

| 上限 | 定義 | 止まるもの | 止まらないもの |
| --- | --- | --- | --- |
| 形式が違う Bearer トークン | `isApiTokenFormat` で 401 | Firestore の読み取り (0 件) | Cloud Run のリクエスト課金と CPU 時間 (数十 ms)、リクエストログ |
| 未知トークンの共有枠 600 req/分 | 形式は正しいが実在未確認のトークンを、インスタンスあたり 600 req/分で 429 (`EXTERNAL_GLOBAL_RATE_LIMIT`) | 枠内でも 1 リクエストにつき Firestore 1 read (collectionGroup の空クエリ) が発生し、超過分は read なしで 429 | Cloud Run のリクエスト課金。インスタンス単位のメモリで数えるため、最大 10 インスタンスなら合計 6,000 req/分まで通り、再起動・スケールで窓がリセットされる |
| トークンごとの枠 60 req/分 | 実在するトークンをインスタンスあたり 60 req/分で 429 (`EXTERNAL_TOKEN_RATE_LIMIT`) | 超過分の Firestore 読み書き・push | 同上 (最大 10 インスタンスで合計 600 req/分) |
| 無料プランの月 20 件 | `plan_limit_exceeded` で 403 (`planLimits.free.alarmsPerMonth`) | 21 件目以降のアラーム作成・push・端末報告・定期削除 | 上限到達後も 1 リクエストにつきトークン検索 1 + 端末 D + トランザクション 2 = D + 3 read と `lastUsedAt` 1 write は発生する。Pro には上限が無い |
| 同じ内容の再送 | 同一 id・同一 fireAt・title・トークンなら月間上限を消費しない | 月間上限の消費とアラーム文書の書き換え | push D 件、配送結果の記録 1 write、読み取り D + 5 は毎回発生する (無限ループする外部サービスはレート制限まで課金される) |
| 端末数 20 台 | `device_limit_exceeded` で 403 (`MAX_DEVICES_PER_USER`) | 1 アラームあたりの push・端末報告・読み取りが 20 台分を超えて増えること | 20 台までは 1 アラームあたり 86 read / 24 write / 21 リクエストになる (D = 1 の約 10 倍) |
| Cloud Run 最大インスタンス 10 (revision) / 20 (service) | `setGlobalOptions({ maxInstances: 10 })` | 同時実行 80 × 10 を超える処理が滞留し、インスタンス時間が青天井に増えない | 公式ドキュメントのとおり、トラフィックの急増時は短時間だけ設定を超えることがある。滞留したリクエストの課金は発生する |
| fire_at の範囲 (30 秒〜365 日先) | `MIN_FIRE_AT_LEAD_SECONDS` / `MAX_FIRE_AT_AHEAD_DAYS` | 発火が遠い文書が保存され続けること (保存は最長 365 + 30 日) | |
| 定期削除 1 回 10,000 件 (500 件 × 20 バッチ) | `CLEANUP_BATCH_SIZE` × `CLEANUP_MAX_BATCHES`、6 時間毎 | 1 回の実行時間の青天井 | 1 日 40,000 件 = 月 120 万件を超える期限切れは処理しきれず滞留する (Pro 300 件/月 × 4,000 人相当)。滞留は保存料 ($0.115 / GiB・月) を増やすだけで、他の課金は増えない |
| 予算アラート 月 ¥10,000 | 50 / 90 / 100% でメール通知 | 何も止めない (Cloud Billing の予算は通知のみで支出の上限ではない) | |

漏洩トークン・暴走した外部サービスの 1 日あたりの上限 (D = 1、最大 10 インスタンスにスケールした場合の理論値):

| 経路 | 1 日の回数 | 1 日の費用 |
| --- | --- | --- |
| 無料プランの上限到達後に登録を試み続ける (D + 3 read、1 write、push なし) | 864,000 回 (600 req/分) | 約 $7 (¥1,000) |
| Pro トークンで別 id のアラームを登録し続ける (登録 + push。端末の報告を除く) | 864,000 回 | 約 $18〜52 (¥2,700〜7,800。t = 0.2〜1.0 秒) |
| 形式は正しい未知トークンを送り続ける (1 read) | 8,640,000 回 (6,000 req/分) | 約 $49 (¥7,400) |

いずれも 1 日で予算 ¥10,000 の 50% (¥5,000) に届くか、数日で届く。予算の通知は早くて数時間〜1 日遅れるため、通知を受けてからトークンを失効 (`DELETE /v1/api-tokens/{id}`) するまでの間の費用は数千円のオーダーになる。トークン漏洩の実害は費用より「本物のアラームが鳴り続ける」ことであり、その対処もトークンの失効で行う。

## 無料枠の消費を抑える設定の確認結果 (2026-09-12)

| 項目 | 確認方法 | 結果 |
| --- | --- | --- |
| Cloud Run 最小インスタンス 0 | `gcloud run services list --project=alarmify-prod --region=asia-northeast1 --format=yaml` に `minScale` の指定が無い | 0 (アイドル課金なし) |
| Cloud Run 最大インスタンス | 同上。revision `autoscaling.knative.dev/maxScale: '10'`、service `run.googleapis.com/maxScale: '20'` | 5 サービスとも 10 / 20。`setGlobalOptions({ maxInstances: 10 })` と一致 |
| 課金方式 | 同上。`run.googleapis.com/cpu-throttling` の指定が無い | request-based (既定) |
| `cleanupExpiredAlarms` の定期実行 | `gcloud scheduler jobs list --project=alarmify-prod --location=asia-northeast1` | `firebase-schedule-cleanupExpiredAlarms-asia-northeast1` every 6 hours ENABLED、`firebase-schedule-sweepDeletedAccountsHourly-asia-northeast1` every 60 minutes ENABLED |
| `cleanupExpiredAlarms` の実行ログ | `gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="cleanupexpiredalarms" AND jsonPayload.message="deleted expired alarms"' --project=alarmify-prod --freshness=7d` | 6 時間毎に `deleted expired alarms` (deleted: 0) が記録されている。期限切れがまだ無いため削除件数は 0 |
| Cloud Logging の保持期間 | `gcloud logging buckets list --project=alarmify-prod` | `_Default` 30 日 (無料の既定)、`_Required` 400 日 (監査ログ。変更不可・無料) |
| Cloud Logging の除外フィルタ | `gcloud logging sinks describe _Default --project=alarmify-prod` | 標準の監査ログ除外のみ。リクエストログの除外は無い |
| Cloud Logging の取り込み量 | Monitoring API `logging.googleapis.com/billing/bytes_ingested` (直近 7 日) | 約 0.9 MB / 7 日 ≈ 4 MB / 月。無料枠 50 GiB の 0.01% で、除外フィルタは不要 |

不足と扱い:

- 予算アラートの通知先が email チャンネルだけで、Slack `#alarmify-notification` には届かない。Cloud Billing の予算が Monitoring の通知チャンネルとして受け付けるのは email 型のみで、Slack へ流すには Pub/Sub トピック + 転送する仕組み (Cloud Functions 等) が要る (https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications )。新しい構成要素の追加になるため別 issue に切り出した ( https://github.com/bannzai/Alarmify/issues/73 )
- 定期削除の処理能力 (月 120 万件) が Pro 4,000 人相当で頭打ちになる。今の規模では問題にならず、増強の方法 (バッチ数・実行間隔・TTL ポリシーへの切り替え) の判断が要るため別 issue に切り出した ( https://github.com/bannzai/Alarmify/issues/74 )
- 予算 ¥10,000 / 月は試算に対して「少なすぎて誤報する」側ではなく、平常時の支出 (月 ¥100 未満) に対して大きい側。50% の通知 (¥5,000) が届く時点で平常時の 50 か月分を使っており、漏洩の検知としては遅い。予算額の見直し (例: ¥3,000 に下げる、または 5% の閾値を足す) は判断事項として issue #62 のコメントに書き、変更はしていない
- Artifact Registry の cleanup policy が未設定。今は 0 MB で費用 0 のため対応せず、上記「固定費」に対処を書いた

## 試算の再計算

単価・仮定 (為替、t、D、Pro 比率) を変えて再計算する時は、上の表の式をそのまま使う:

- 1 アラーム = Firestore ((4D + 6) × read + (4 + D) × write + 1 × delete) + Cloud Run ((1 + D) × t × (1 vCPU 単価 + 0.25 GiB × メモリ単価) + (1 + D) × リクエスト単価) + 保存 (2 KiB × 1 か月)
- 月額 = Σ ユーザー × 月間アラーム数 × 1 アラーム + 定期実行分 (Scheduler $0.20 + 2,376 vCPU 秒 + 120 read)
- 損益分岐 (Pro 人数) = 固定費 年額 ÷ (Pro 1 人の手取り − Pro 1 人の変動費 − 混合比率に応じた無料ユーザーの変動費)
