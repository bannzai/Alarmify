# Firebase Functions のデプロイ手順

Cloud Functions (gen2) を `firebase/.firebaserc` の alias で指定した Firebase プロジェクトへデプロイする。ローカルとも GitHub Actions とも同じ `firebase deploy --only functions --project <alias>` を使う。

`firebase/.firebaserc` の alias は 2 つ。デプロイ先は必ず alias で明示する (取り違え防止)。

| alias | GCP プロジェクト | 用途 |
| --- | --- | --- |
| `default` | `demo-alarmify` | ローカルのエミュレータ専用 (実プロジェクトではない) |
| `prod` | `alarmify-prod` | 本番 (asia-northeast1) |

## 現状: 本番へデプロイ済み (ローカル・CI とも稼働)

`alarmify-prod` へは 2026-09-03 に初回デプロイ済み。2026-09-12 に GitHub Actions から更新し、`revenueCatWebhook` を含む6関数が ACTIVE (gen2)、対応する Cloud Run の6サービスが Ready であることを確認した。`alarmsApi/v1/alarms` と `revenueCatWebhook` は Authorization 無しの POST に401を返した。

2026-09-12 の配布・再配布の結果は #58 に記録している。現在の App Check の適用段階と切り替え判断は `documents/app-check.md` を参照する。

Secret `REVENUECAT_WEBHOOK_AUTHORIZATION` は登録済み。RevenueCat Dashboard 側の webhook 設定と値の受け渡しは #25 に記録している。関数の配布だけでは RevenueCat からのプラン同期は有効にならない (設定手順は `documents/revenuecat-webhook.md`)。

`budgetAlertToSlack` (#73) は Secret `SLACK_BOT_TOKEN` を束ねているため、登録が済むまで `firebase deploy --only functions` は Functions 全体で止まる。Pub/Sub トリガーの関数の初回作成は CI のデプロイ用サービスアカウントの権限では行えず、オーナーのアカウントでローカルから行う (登録・初回デプロイの手順は `documents/budget-alert-slack.md`)。

`firebase/firebase.json` の `firestore` (全パス deny の `firebase/firestore.rules` と、複合インデックスの `firebase/firestore.indexes.json`) は Functions のデプロイ経路に含まれないため、初回とそれらを変更した時は `firebase/` で `firebase deploy --only firestore --project prod` を別途実行する (rules を配布しないと以前の rules が残り、エミュレータはインデックスの不足も検出しない)。

デプロイ状態の確認 (read-only):

```sh
gcloud functions list --project alarmify-prod --v2 --format='table(name,state,updateTime,environment)'

# firestore.rules の適用状態 (応答の rulesetName と updateTime を見る)
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "x-goog-user-project: alarmify-prod" \
  https://firebaserules.googleapis.com/v1/projects/alarmify-prod/releases/cloud.firestore

# 外部サービス向け API がトークンなしで 401 を返すこと (認証前に落ちるので Firestore には何も書かれない)
curl -i -X POST https://asia-northeast1-alarmify-prod.cloudfunctions.net/alarmsApi/v1/alarms \
  -H 'Content-Type: application/json' -d '{"fire_at":"2030-01-01T00:00:00Z","title":"test"}'
```

GitHub Actions からのデプロイ (`functions-deploy.yml`) も稼働済み。前提の次の 2 つは 2026-09-04 に適用した。

- デプロイ専用サービスアカウントの作成と IAM 付与 (下記「サービスアカウントと IAM」)。`cleanupExpiredAlarms` と `sweepDeletedAccountsHourly` が `onSchedule` のため `roles/cloudscheduler.admin` を含める
- environment secret `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` の登録 (下記「Secret を登録する」)

初回 run: https://github.com/bannzai/Alarmify/actions/runs/33799188366 (main と本番が同じコードだったため、5 関数すべて `Skipped (No changes detected)` → `Deploy complete!`)

## ローカルからデプロイする

```sh
make deploy-functions                                  # alias prod (= alarmify-prod) へ functions 全体をデプロイ
make deploy-functions FUNCTIONS=alarmsApi               # 対象を絞る (カンマ区切りで複数指定できる)
make deploy-functions FIREBASE_ALIAS=prod               # alias を明示する場合
```

target は実行前に alias から GCP プロジェクト ID を解決してログに出し、alias が `firebase/.firebaserc` に無ければデプロイせずに止まる。

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

## サービスアカウントと IAM (実行・ビルド・デプロイの分離)

Functions に関わるサービスアカウント (SA) は役割ごとに分け、それぞれに必要な権限だけを付ける (#66)。必要権限の照合の根拠 (2026-09-12 のデプロイの Cloud Audit Logs と firebase-tools v15.30.0 のソース) は https://github.com/bannzai/Alarmify/issues/66#issuecomment-5654369992 に記録している。

| 役割 | SA | プロジェクトのロール | リソース単位の binding |
| --- | --- | --- | --- |
| 実行 (全関数の `serviceAccount`。`firebase/functions/src/index.ts` の `setGlobalOptions` で固定) | `functions-runtime@alarmify-prod.iam.gserviceaccount.com` | `roles/datastore.user` (Firestore)、`roles/firebasecloudmessaging.admin` (FCM 送信)、`roles/firebaseauth.admin` (Auth の getUser / deleteUser)、`roles/logging.logWriter`、`roles/cloudtrace.agent`、`roles/eventarc.eventReceiver` (Pub/Sub トリガーの `budgetAlertToSlack`) | 各 Secret (`REVENUECAT_WEBHOOK_AUTHORIZATION` / `SLACK_BOT_TOKEN`) に `roles/secretmanager.secretAccessor`。定期実行・Pub/Sub の Cloud Run サービスに `roles/run.invoker` (デプロイ時に firebase-tools が付ける) |
| ビルド (Cloud Build。firebase-tools からは指定できないためプロジェクト既定のまま) | `320409781062-compute@developer.gserviceaccount.com` | `roles/cloudbuild.builds.builder`、`roles/artifactregistry.writer`、`roles/logging.logWriter`、`roles/monitoring.metricWriter`、`roles/cloudtrace.agent` (後ろ 2 つは castle の `check-deploy-iam.sh` が期待するだけで未使用) | - |
| デプロイ (GitHub Actions) | `github-firebase-deployer@alarmify-prod.iam.gserviceaccount.com` | `roles/cloudfunctions.admin` (関数の作成・更新と、新規 HTTPS 関数・定期実行の invoker 設定に要る `run.services.setIamPolicy`)、`roles/cloudscheduler.admin` (定期実行ジョブの更新)、`roles/firebase.viewer` (プロジェクト参照)、`roles/secretmanager.viewer` (`defineSecret` の存在確認) | `functions-runtime` / appspot / compute の各 SA に `roles/iam.serviceAccountUser` (ActAs。appspot は未使用でも firebase-tools が deploy 前に検査する) |

実行 SA は Editor を持たないため、次の作業はデプロイではなくオーナーの `gcloud` で先に行う。

- 新しい Secret を `defineSecret` で追加する時: `gcloud secrets add-iam-policy-binding <Secret 名> --project=alarmify-prod --member=serviceAccount:functions-runtime@alarmify-prod.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor` (deployer は `secretmanager.viewer` のため付与できない。Secret の値の登録・更新・未使用バージョンの破棄も `secretmanager.versions.add` / `destroy` が要るためオーナーがローカルで行う)
- 新しい GCP API が要る時: `gcloud services enable <API> --project=alarmify-prod` (deployer は `serviceusage.services.enable` を持たない)
- 実行時に新しい権限が要る時 (Cloud Tasks 等): `functions-runtime` へロールを付ける。Editor による暗黙の権限は無い

実行 SA の作成と付与 (冪等):

```sh
gcloud iam service-accounts create functions-runtime --project=alarmify-prod --display-name="Signalarm Functions runtime"
for role in roles/datastore.user roles/firebasecloudmessaging.admin roles/firebaseauth.admin roles/logging.logWriter roles/cloudtrace.agent roles/eventarc.eventReceiver; do
  gcloud projects add-iam-policy-binding alarmify-prod --member=serviceAccount:functions-runtime@alarmify-prod.iam.gserviceaccount.com --role="$role" --condition=None
done
for secret in REVENUECAT_WEBHOOK_AUTHORIZATION SLACK_BOT_TOKEN; do
  gcloud secrets add-iam-policy-binding "$secret" --project=alarmify-prod --member=serviceAccount:functions-runtime@alarmify-prod.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
done
gcloud iam service-accounts add-iam-policy-binding functions-runtime@alarmify-prod.iam.gserviceaccount.com --project=alarmify-prod --member=serviceAccount:github-firebase-deployer@alarmify-prod.iam.gserviceaccount.com --role=roles/iam.serviceAccountUser --condition=None
```

デプロイ専用 SA の初期作成は firebase-functions-deploy-iam-setup skill (bannzai/castle) の `grant-deploy-iam.sh --create-sa --scheduler` で行った (2026-09-04)。同 skill は `roles/firebase.admin` / `roles/secretmanager.admin` を前提にしているため、縮小後は `check-deploy-iam.sh` がその 2 つを `[MISSING]` と報告し、`grant-deploy-iam.sh` を再実行すると admin を付け直す。skill の追随は https://github.com/bannzai/castle/issues/1055 で扱い、それまでは同 skill を再実行しない。

### 縮小の適用順序と復旧

2026-09-14 時点の適用状況: 段階 1 は適用済み (`eventarc.eventReceiver` だけ Claude Code の classifier に拒否され未付与)。段階 2 以降は、Secret `SLACK_BOT_TOKEN` の登録 (#95) が済んで `firebase deploy` が通るようになってから、各段階の間に IAM の伝播 (通常 2 分、最大 7 分以上) を置いて順に進める。順序を入れ替えない (実行 SA を移す前に compute の Editor を外すと、稼働中の関数が Firestore / FCM / Auth を失う)。

1. 実行 SA の作成と付与 (上記のコマンド)
2. 移行デプロイ (`gh workflow run functions-deploy.yml --ref main -f environment=prod`)。確認: `gcloud functions list --project alarmify-prod --v2 --format='table(name,state,serviceConfig.serviceAccountEmail)'` で全関数が `functions-runtime@`、`gcloud scheduler jobs list --project alarmify-prod --location asia-northeast1 --format='table(name,httpTarget.oidcToken.serviceAccountEmail)'` で OIDC の SA が同じ。`gcloud scheduler jobs run firebase-schedule-sweepDeletedAccountsHourly-asia-northeast1 --project alarmify-prod --location asia-northeast1` と `... cleanupExpiredAlarms ...` を実行して Cloud Run のログに ERROR が無いこと。復旧: `setGlobalOptions` の `serviceAccount` を外して再デプロイ (段階 3 より前なら compute SA の Editor が残っているため即時に戻る)
3. compute SA の Editor 除去: `gcloud projects remove-iam-policy-binding alarmify-prod --member=serviceAccount:320409781062-compute@developer.gserviceaccount.com --role=roles/editor --condition=None`。ビルドを伴う変更 (コード差分が無いと `Skipped (No changes detected)` でビルドが走らない) を再デプロイして確認。復旧: `remove` を `add` に変えて実行
4. deployer の縮小 (1 ロールずつ、それぞれデプロイで確認): `gcloud projects add-iam-policy-binding alarmify-prod --member=serviceAccount:github-firebase-deployer@alarmify-prod.iam.gserviceaccount.com --role=roles/firebase.viewer --condition=None` → 同 `remove-iam-policy-binding ... --role=roles/firebase.admin` → デプロイ確認 → `add ... roles/secretmanager.viewer` → `remove ... roles/secretmanager.admin` → デプロイ確認。復旧: `remove` と `add` を入れ替える
5. (任意) `alarmify-prod@appspot.gserviceaccount.com` の Editor 除去 (App Engine アプリも gen1 関数も無く未使用。ActAs の検査は SA の存在だけを見る): `gcloud projects remove-iam-policy-binding alarmify-prod --member=serviceAccount:alarmify-prod@appspot.gserviceaccount.com --role=roles/editor --condition=None`

`320409781062@cloudservices.gserviceaccount.com` (Google APIs Service Agent) の Editor は GCP が内部利用する既定のため変更しない。

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
| `Invalid project selection, ... you have access` | deployer SA にプロジェクトアクセスが無い | `roles/firebase.viewer` を付け直す (上記「サービスアカウントと IAM」) |
| `secretmanager.secrets.setIamPolicy` の PERMISSION_DENIED | 新しい Secret に実行 SA の accessor が無く、deployer (viewer) が付与できない | オーナーが `gcloud secrets add-iam-policy-binding` で `functions-runtime` に accessor を付けてから再デプロイする |
| `Access to bucket gcf-v2-sources-... denied` / `artifactregistry.repositories.downloadArtifacts` denied | ビルド SA (compute) の `roles/cloudbuild.builds.builder` が外れた | compute SA に `roles/cloudbuild.builds.builder` を付け直す |
| 関数の実行時に Firestore / FCM / Auth の PERMISSION_DENIED | 実行 SA に必要なロールが無い (Editor の暗黙の権限に頼っていた) | `functions-runtime` へ該当ロールを付ける |
| `iam.serviceAccounts.ActAs ...` が付与後も消えない | Secret に入れた鍵の SA と、権限を付けた SA が違う | 鍵の `client_email` を確認する (workflow の Restore service account key step がログに出す) |
| `In non-interactive mode but have no value for ... <VAR>` | `defineString()` 等の params の値が CI に無い (IAM とは無関係) | 値を GitHub Variable 等で渡し、deploy 直前に `.env.<project>` を生成する step を足す |

`PERMISSION_DENIED` は IAM 不足、`SERVICE_DISABLED` は API 未有効で切り分ける。

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-12
claude --resume 0578bd60-8548-49a9-a76b-62987bb07c49
```
