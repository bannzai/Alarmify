# 0009. GitHub Actions の Firebase デプロイは SA 鍵ではなく Workload Identity Federation で認証する

## Status
Accepted (2026-09-14)

## Context
`functions-deploy.yml` はデプロイ専用サービスアカウント `github-firebase-deployer` の JSON 鍵 (2026-09-03 発行、有効期限なし) を environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` に置いて認証していた (#12)。鍵は漏れると持ち主が誰でも無期限にデプロイ権限を使え、失効は手動でしか行えない。#66 の IAM 縮小で deployer の権限を絞るのに合わせ、鍵そのものを無くす方式を比較した。

1. 現状維持 (長期の SA 鍵を GitHub Secret に保存)
2. Workload Identity Federation (WIF) で GitHub の OIDC トークンを SA の短命な access token に交換する (SA impersonation)
3. WIF の直接連携 (SA を介さず、Workload Identity Pool の principal に直接ロールを付ける)

3 は Google Cloud の対応表で Cloud Run / Cloud Run functions が「Workload Identity Federation direct resource access に対応しない。SA impersonation を使う」とされており採れない ( https://docs.cloud.google.com/iam/docs/federated-identity-supported-services )。2 は firebase-tools が `GOOGLE_APPLICATION_CREDENTIALS` の `external_account` 資格情報を Application Default Credentials として読むため、deploy コマンドは変えずに済む (15.22.2 で壊れた回帰は 15.22.3 で修正済みで、workflow は 15.30.0 を固定している)。

## Decision
方式 2 を採る。

- Workload Identity Pool `github` と OIDC Provider `alarmify` を `alarmify-prod` に作り、Provider の attribute 条件をリポジトリ ID (`1354444647`)・owner ID (`10897361`)・environment 名 (`firebase-prod`) で絞る。リポジトリ名ではなく ID で絞るのは、リポジトリ名の変更 (#82) で認証が壊れないようにするため。environment claim は environment を使う job にしか付かないため、`firebase-prod` のデプロイブランチ制限 (main のみ) と合わせて、main 以外の branch から改変した workflow が本番の資格情報を得る経路を塞ぐ
- deployer SA に `roles/iam.workloadIdentityUser` を `principalSet://.../attribute.repository_id/1354444647` へ付与する
- workflow は `permissions: id-token: write` を足し、鍵の復元 step を `google-github-actions/auth` (commit SHA 固定) に置き換える。資格情報ファイルは action の post step が削除する
- 鍵と Secret は、WIF でのデプロイが 1 回成功してから削除する (手順は `documents/functions-deploy.md`)

## Consequences

**良い点:**
- 長期の秘密が GitHub にも GCP にも残らない。access token は 1 時間で失効し、OIDC トークンは run ごとに発行される
- 認証できる主体が「このリポジトリの `firebase-prod` environment を使う job」に限定され、Secret のコピーでは再現できない
- deploy コマンドと IAM の付与先 (deployer SA) は変わらない

**悪い点 / 引き受けるリスク:**
- GitHub の OIDC claim の形式 (`environment` の有無・`sub` の形) が変わると Provider の条件で弾かれ、デプロイが止まる。復旧は鍵方式へ戻すか条件を直す
- firebase-tools の ADC まわりの回帰 (15.22.2 の例) に影響を受ける。バージョンを固定し、上げる時は WIF でのデプロイを 1 回確認する
- ローカルからのデプロイ (`make deploy-functions`) はオーナーの `gcloud` 認証のままで、本 ADR の対象外
