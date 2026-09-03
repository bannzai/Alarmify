# Firebase Functions のデプロイ手順

Cloud Functions (gen2) を `.firebaserc` の alias で指定した Firebase プロジェクトへデプロイする。ローカルとも GitHub Actions とも同じ `firebase deploy --only functions --project <alias>` を使う。

`.firebaserc` の alias は 2 つ。デプロイ先は必ず alias で明示する (取り違え防止)。

| alias | GCP プロジェクト | 用途 |
| --- | --- | --- |
| `default` | `demo-alarmify` | ローカルのエミュレータ専用 (実プロジェクトではない) |
| `prod` | `alarmify-prod` | 本番 (asia-northeast1) |

## 現状: 本番へデプロイ済み。CI からのデプロイ経路だけ未整備

`alarmify-prod` へは 2026-09-03 にローカル (`make deploy-functions`) から初回デプロイ済みで、`appApi` (アプリ向け API)・`alarmsApi` (外部サービス向け API)・`cleanupExpiredAlarms` (期限切れアラームの定期削除)・`deleteAccount` (アカウント削除の Callable)・`sweepDeletedAccountsHourly` (アカウント削除の掃除の定期実行) の 5 つが ACTIVE (gen2)。`firebase.json` の `firestore` (全パス deny の `firestore.rules` と、複合インデックスの `firestore.indexes.json`) は Functions のデプロイ経路に含まれないため、初回とそれらを変更した時は `firebase deploy --only firestore --project prod` を別途実行する (rules を配布しないと以前の rules が残り、エミュレータはインデックスの不足も検出しない)。

デプロイ状態の確認 (read-only):

```sh
gcloud functions list --project alarmify-prod --format='table(name,state,updateTime,environment)'

# ruleset の適用日時 (firestore.rules)
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "x-goog-user-project: alarmify-prod" \
  https://firebaserules.googleapis.com/v1/projects/alarmify-prod/releases

# 外部サービス向け API がトークンなしで 401 を返すこと (認証前に落ちるので Firestore には何も書かれない)
curl -i -X POST https://asia-northeast1-alarmify-prod.cloudfunctions.net/alarmsApi/v1/alarms \
  -H 'Content-Type: application/json' -d '{"fire_at":"2030-01-01T00:00:00Z","title":"test"}'
```

GitHub Actions からのデプロイ (`functions-deploy.yml`) は、次の 2 つが未実施のためまだ起動できない:

- デプロイ専用サービスアカウントの作成と IAM 付与 (下記「デプロイ専用サービスアカウントの用意」)。`cleanupExpiredAlarms` と `sweepDeletedAccountsHourly` が `onSchedule` のため `--scheduler` を付けて付与する
- environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` の登録 (下記「Secret を登録する」)

## ローカルからデプロイする

```sh
make deploy-functions                                  # alias prod (= alarmify-prod) へ functions 全体をデプロイ
make deploy-functions FUNCTIONS=alarmsApi               # 対象を絞る (カンマ区切りで複数指定できる)
make deploy-functions FIREBASE_ALIAS=prod               # alias を明示する場合
```

target は実行前に alias から GCP プロジェクト ID を解決してログに出し、alias が `.firebaserc` に無ければデプロイせずに止まる。

## GitHub Actions からデプロイする

`.github/workflows/functions-deploy.yml` を `workflow_dispatch` で起動する。認証はデプロイ専用サービスアカウントの鍵で行い、鍵は environment `firebase-prod` の environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` に置く。

```sh
gh workflow run functions-deploy.yml --ref main -f environment=prod
# 対象を絞る場合
gh workflow run functions-deploy.yml --ref main -f environment=prod -f functions=alarmsApi

RUN_ID="$(gh run list --workflow functions-deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID"
```

`workflow_dispatch` の workflow はデフォルトブランチに存在してからでないと dispatch できない。追加した PR をマージしてから初回起動する。

## デプロイ専用サービスアカウントの用意

デプロイ専用 SA は `github-firebase-deployer@alarmify-prod.iam.gserviceaccount.com`。必要な IAM は firebase-functions-deploy-iam-setup skill (bannzai/castle) が付与する。付与するロールの一覧と各ロールの理由は同 skill の `scripts/grant-deploy-iam.sh` のコメントを正とする。

```sh
# 現状診断 (read-only)。不足は [MISSING] で出る
bash ~/.agents/skills/firebase-functions-deploy-iam-setup/scripts/check-deploy-iam.sh --project alarmify-prod

# 付与内容の確認 → 適用 (冪等)
bash ~/.agents/skills/firebase-functions-deploy-iam-setup/scripts/grant-deploy-iam.sh --project alarmify-prod --create-sa --scheduler --dry-run
bash ~/.agents/skills/firebase-functions-deploy-iam-setup/scripts/grant-deploy-iam.sh --project alarmify-prod --create-sa --scheduler

# 付与後、すべて [OK] になることを確認する (IAM の反映に数分かかることがある)
bash ~/.agents/skills/firebase-functions-deploy-iam-setup/scripts/check-deploy-iam.sh --project alarmify-prod
```

`--scheduler` は `onSchedule` の関数 (`cleanupExpiredAlarms` / `sweepDeletedAccountsHourly`) のデプロイに要る `roles/cloudscheduler.admin` を追加する。

## Secret を登録する

鍵は非冪等 (実行のたびに新しい鍵ができる) なので、既存の鍵があるかを確認してから発行する。environment `firebase-prod` の作成と `main` だけへのデプロイブランチ制限は適用済み (下の setup-environment.sh は再実行しても同じ状態に収束する)。

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/setup-environment.sh \
  --repo bannzai/Alarmify --environment firebase-prod --branch main

mkdir -p ./tmp   # tmp/ は .gitignore 済みで、fresh checkout には存在しない
# 途中で失敗しても本番の鍵をディスクに残さないよう、生成前に削除を予約しておく
trap 'rm -f ./tmp/deployer.json' EXIT
gcloud iam service-accounts keys create ./tmp/deployer.json \
  --iam-account=github-firebase-deployer@alarmify-prod.iam.gserviceaccount.com --project=alarmify-prod
B64=$(base64 < ./tmp/deployer.json)
[ -n "$B64" ] || { echo "Error: 鍵が空です" >&2; exit 1; }
printf '%s' "$B64" | gh secret set FIREBASE_SERVICE_ACCOUNT_JSON_BASE64 --repo bannzai/Alarmify --env firebase-prod
```

`trap` は対話シェルでそのまま貼ると、そのシェルを閉じるまで発火しない。上のブロックはスクリプトファイル (`bash issue-key.sh`) か `bash -c` で実行し、実行後に `ls ./tmp/deployer.json` で鍵が残っていないことを確かめる。

登録した secret の所在は env-secret-registry skill の `secret-locations.tsv` に記録する (値は記録しない)。

## よくある失敗

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `Invalid project selection, ... you have access` | deployer SA にプロジェクトアクセスが無い | `grant-deploy-iam.sh` を再実行する |
| `iam.serviceAccounts.ActAs ...` が付与後も消えない | Secret に入れた鍵の SA と、権限を付けた SA が違う | 鍵の `client_email` を確認する (workflow の Restore service account key step がログに出す) |
| `In non-interactive mode but have no value for ... <VAR>` | `defineString()` 等の params の値が CI に無い (IAM とは無関係) | 値を GitHub Variable 等で渡し、deploy 直前に `.env.<project>` を生成する step を足す |

`PERMISSION_DENIED` は IAM 不足、`SERVICE_DISABLED` は API 未有効で切り分ける。

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-12
claude --resume 0578bd60-8548-49a9-a76b-62987bb07c49
```
