# Firebase Functions のデプロイ手順

Cloud Functions (gen2) を `.firebaserc` の alias で指定した Firebase プロジェクトへデプロイする。ローカルとも GitHub Actions とも同じ `firebase deploy --only functions --project <alias>` を使う。

`.firebaserc` の alias は 2 つ。デプロイ先は必ず alias で明示する (取り違え防止)。

| alias | GCP プロジェクト | 用途 |
| --- | --- | --- |
| `default` | `demo-alarmify` | ローカルのエミュレータ専用 (実プロジェクトではない) |
| `prod` | `alarmify-prod` | 本番 (asia-northeast1) |

## デプロイの前提

バックエンドの実装は `functions/` と `firebase.json` にある (アカウント削除の `deleteAccount` と、その掃除の定期実行 `sweepDeletedAccountsHourly`。外部サービス向けの API は https://github.com/bannzai/Alarmify/issues/2 で追加する)。初回のデプロイ前に次の 2 つを済ませる:

- デプロイ専用サービスアカウントの作成と IAM 付与 (下記「デプロイ専用サービスアカウントの用意」)。`sweepDeletedAccountsHourly` が `onSchedule` のため `--scheduler` を付けて付与する
- environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` の登録 (下記「Secret を登録する」)

## ローカルからデプロイする

```sh
make deploy-functions                                  # alias prod (= alarmify-prod) へ functions 全体をデプロイ
make deploy-functions FUNCTIONS=v1-alarms-create        # 対象を絞る (カンマ区切りで複数指定できる)
make deploy-functions FIREBASE_ALIAS=prod               # alias を明示する場合
```

target は実行前に alias から GCP プロジェクト ID を解決してログに出し、alias が `.firebaserc` に無ければデプロイせずに止まる。

## GitHub Actions からデプロイする

`.github/workflows/functions-deploy.yml` を `workflow_dispatch` で起動する。認証はデプロイ専用サービスアカウントの鍵で行い、鍵は environment `firebase-prod` の environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` に置く。

```sh
gh workflow run functions-deploy.yml --ref main -f environment=prod
# 対象を絞る場合
gh workflow run functions-deploy.yml --ref main -f environment=prod -f functions=v1-alarms-create

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

`--scheduler` は `onSchedule` の関数 (`sweepDeletedAccountsHourly`) のデプロイに要る `roles/cloudscheduler.admin` を追加する。

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
