# 0001. バックエンドは Firebase (Cloud Functions gen2 + Firestore + Firebase Auth + FCM) とする

## Status
Accepted (2026-09-02)

## Context
Alarmify は外部サービスからの HTTPS リクエストを受け、ユーザーの iPhone へ push を配送して AlarmKit のアラームを登録する。ユーザー・API トークン・デバイストークン・アラーム要求を保持する DB と、常時受け付ける API、push 配送 (APNs / FCM) が必要になる。想定規模はローンチ時で数百ユーザー・1 日数千リクエスト。

決めるべきは DB・ストレージ・ホスティング / バックエンド・認証・Analytics の構成。ユーザーからは「Firebase でよいが、より安い構成があれば知りたい」という要望があり、2026-09-02 に料金と運用面を比較した (調査の全文は https://github.com/bannzai/IdeaMemo/issues/194 のコメント)。

| 選択肢 | 0 ユーザー | 500 ユーザー / 1 日 3 千 req | 5,000 ユーザー / 1 日 5 万 req | 備考 |
| --- | --- | --- | --- | --- |
| Firebase Blaze | $0 (要クレジットカード) | ほぼ $0 (無料枠内) | $0〜数ドル | Functions gen2 は Blaze 必須。FCM 無料。Auth 5 万 MAU まで無料 |
| Cloudflare Workers Free + D1 | $0 (カード不要) | $0 | $0〜$5 (CPU 時間次第) | Workers から APNs へ HTTP/2 で直送できる実装例あり。認証・DB は自前実装 |
| Supabase | $0 (1 週間非アクティブで停止) | Pro $25 | $25〜 | Webhook 常時受付には Free が不向き |
| Deno Deploy | $0 | $0 | $0 | 月 100 万 req 無料。商用可 |
| Fly.io / Hetzner VPS | $2〜5 / €3.79 固定 | 同左 | 同左〜 | 常時稼働の固定費 |
| AWS Lambda | $0 | $0〜数十セント | $0〜数ドル | 新規アカウントは API Gateway の無料枠なし |

## Decision
- **ホスティング / バックエンド**: Firebase Cloud Functions gen2 (Cloud Run functions)。API は Functions の HTTPS エンドポイント
- **DB**: Firestore (asia-northeast1)。ユーザー・API トークン・デバイストークン・アラーム要求 (履歴は 30 日で削除) を保持する。DB のルールは `.claude/rules/firestore-db-rules.md`
- **ストレージ**: なし (画像・ファイルを扱わない)
- **認証**: Firebase Auth の匿名認証で自動作成し、API トークンはサーバーで発行する。Firebase Auth の認証状態は keychain に永続化されるため、同じ端末の再インストールではアカウントが引き継がれる。端末の買い替え時はトークンを発行し直す運用とし、Sign in with Apple による端末間の引き継ぎは MVP に含めない (Guideline 4.8 はサードパーティのソーシャルログインを提供する場合の義務で、匿名認証のみなら対象外。必要になった時点で別 issue で検討する)
- **App Check**: アプリ → バックエンド (トークン発行・端末登録・履歴取得) の Functions は Firebase App Check (App Attest。開発時はデバッグプロバイダ) で保護し、アプリ以外からの呼び出しを拒否する。外部サービスからのアラーム API は任意のサーバーから呼ばれる前提のため App Check の対象外とし、API トークン + レート制限で守る。導入は firebase-app-check-setup skill で行う
- **push 配送**: FCM 経由で APNs へ送る (FCM は無料。Functions から HTTP/2 で APNs に直接つなぐ実装を持たない)。検証方式 3 (ActivityKit Remote Push) が必要になった場合は APNs への直接送信を別 ADR で決める
- **Analytics / クラッシュレポート**: MVP では導入しない
- **GCP プロジェクト**: `alarmify-prod` (課金アカウント bannzai.star.kojiki にリンク)。課金・エラーアラートは gcp-alert-setup skill で Slack `#alarmify-notification` へ通知する。ローカルは `demo-alarmify` のエミュレータで運用する

最安の構成は Cloudflare Workers (Free) だったが、想定規模では Firebase も実質 $0 で料金差がなく、差が出るのは運用面 (Blaze 化 + 予算アラートの要否 / 認証・DB の自前実装の要否) だった。他アプリでの Firebase の実績と、firebase-project-setup / gcp-alert-setup / firebase-functions-deploy-iam-setup skill が揃っていることを優先して Firebase を選んだ。

## Consequences

**良い点:**
- 認証 (匿名)・App Check・DB・Functions・push を 1 つの SDK / CLI で扱え、MVP の実装量が最小になる
- 既存プロジェクトと同じ運用 (予算アラート・IAM・デプロイ経路) をそのまま適用できる
- FCM 経由のため APNs の証明書 / キー管理を Functions 側に持たない

**悪い点 / 引き受けるリスク:**
- Blaze プラン (従量課金) のため、無料枠を超えた場合に請求が発生する。予算アラートで検知する
- Cloud Functions gen2 のコールドスタート (min instances 0) により、初回リクエストの遅延が数秒になる。アラームは分単位の精度で足りるため許容する
- FCM を経由すると APNs の `mutable-content` / `content-available` / ActivityKit の push type を FCM の APNs オーバーライドで表現する必要がある。表現できない push type が出た場合は APNs 直送へ切り替える (別 ADR)
- Firestore の location は作成後に変更できない。ユーザーは世界中に分布し得るが、レイテンシは push 配送全体 (数秒) に対して無視できる
