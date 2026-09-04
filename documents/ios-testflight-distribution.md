# iOS TestFlight 配布手順

`.github/workflows/ios-deploy.yml` で Alarmify を Release / 実機向けにアーカイブし、IPA を TestFlight (App Store Connect) へアップロードする。署名は手動署名で、Secrets の P12 証明書と App Store 用 provisioning profile を CI 上に復元して使う。方式の設計判断は ios-deploy-actions skill (bannzai/castle) の `references/signing-design.md` を正とする。

## 現状: 配布の前提は揃っている (2026-09-04)

次の 4 つは 2026-09-04 に適用済み。再発行・更新の手順は以降の各節を参照する。

1. **App Store Connect のアプリレコード**: 「Signalarm」(app id 6808548984、bundle id `com.bannzai.Alarmify`、主言語 en-US)。公開 App Store Connect API に作成エンドポイントは無いが、`fastlane produce create` (Apple ID の Web セッション) で作成できる。製品名の経緯は https://github.com/bannzai/Alarmify/issues/14
2. **App ID と App Group**: 3 つの App ID (`com.bannzai.Alarmify` = `S63PHTW726` / `.NotificationService` = `XFD8933ZYP` / `.Widget` = `ZH2FZGQF2D`) を `POST /v1/bundleIds` で登録し、APP_GROUPS (3 つ) と PUSH_NOTIFICATIONS (app) を `POST /v1/bundleIdCapabilities` で有効化。App Group `group.com.bannzai.Alarmify` (`47A5B5LDSS`) の作成と割り当ては公開 API に無いため `fastlane produce group` / `associate_group` で行った
3. **配布証明書と provisioning profile**: チーム共有の Apple Distribution 証明書 `68L9PY6PX2` (期限 2027-01-17) で 3 本発行済み (`Alarmify.AppStore` = `9YDV59L4TY` / `Alarmify.NotificationService.AppStore` = `29L69S92F2` / `Alarmify.Widget.AppStore` = `2X9ALHKFYG`。期限は証明書と同じ 2027-01-17)。すべて `entitlements-check=ok`
4. **environment secrets**: environment `ios-deploy` に「Secrets を登録する」の 10 個を登録済み

初回 dispatch (build 1) は archive・export まで通り、Upload to TestFlight で App Store の検証 ITMS-90474 (向きの未指定) と ITMS-90360 (Notification Service Extension の `CFBundleDisplayName` 欠落) で失敗した。対処は `project.pbxproj` で `TARGETED_DEVICE_FAMILY = 1` (iPhone 専用。mementomorning と同じ判断) と `INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`、Extension に `INFOPLIST_KEY_CFBundleDisplayName` を設定。build 1 はアップロードされていないため、ビルド番号の offset はそのまま。

## 署名アセットを発行する

証明書はチームに 1 枚を使い回す。開発チームには有効な Apple Distribution 証明書が 2 枚あり (証明書 ID `4U43R7FQ5Q` / `68L9PY6PX2`)、うち serial `1E45CE77DD6B86B207FFBAC2D25E52DF` の 1 枚 (`68L9PY6PX2`、有効期限 2027-01-17) は開発機の login キーチェーンに秘密鍵ごと入っている。まずこの秘密鍵から `.p12` を書き出して使い回し、書き出せない場合だけ新規発行する (Apple Distribution 証明書は発行枚数に上限がある)。

```sh
# 既存証明書の一覧 (証明書 ID / 名義 / serial / 有効期限)
bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh list-certificates

# 原本が見つからず新規発行する場合だけ (既存があるため --allow-additional が要る)
bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-certificate \
  --cn "yudai hirose CI Distribution" --out ./tmp/signing --allow-additional
```

### 既存証明書を使い回す場合の書き出し

`register-secrets.sh` は `./tmp/signing/distribution.p12` と `./tmp/signing/p12-password.txt` を読むため、キーチェーンの証明書を使い回す場合はこの 2 つを自分で用意する。

キーチェーンからの書き出しは Keychain Access の GUI で行う。`security export` は対象を 1 つに絞れず、キーチェーン内の全 identity (別チームの証明書と秘密鍵を含む) を書き出してしまうため使わない。

1. Keychain Access で「ログイン」キーチェーンの `Apple Distribution: yudai hirose (<Team ID>)` (有効期限 2027-01-17 のもの) を選ぶ
2. 右クリック →「"Apple Distribution: ..." を書き出す...」→ フォーマット「個人情報交換 (.p12)」→ 保存先を `./tmp/signing/distribution.p12` にする
3. 書き出し時に設定したパスワードを、改行なしで `./tmp/signing/p12-password.txt` に保存する

```sh
mkdir -p ./tmp/signing
# 上の GUI 操作で ./tmp/signing/distribution.p12 を書き出してから、そのパスワードを保存する
printf '%s' '<書き出し時に設定したパスワード>' > ./tmp/signing/p12-password.txt
chmod 600 ./tmp/signing/distribution.p12 ./tmp/signing/p12-password.txt
# 秘密鍵と証明書が両方入っていること (Key Attributes と Certificate bag が出ること) を確認する
openssl pkcs12 -info -in ./tmp/signing/distribution.p12 -passin "file:./tmp/signing/p12-password.txt" -noout
```

`create-certificate` で新規発行した場合は、`--out` に指定したディレクトリへ `distribution.p12` と `p12-password.txt` が同じ名前で作られるため、この手順は不要。

GUI を使わない書き出し方: `security export` は対象を絞れず全 identity (別チームの鍵を含む) を書き出してしまうため使わないが、Security framework の `SecItemExport` を Swift スクリプトから呼べば serial で指定した 1 つの identity だけを PKCS#12 に書き出せる (許可ダイアログもその鍵 1 つ分だけ出る)。2026-09-04 の初回配布はこの方法で書き出した。スクリプトは ios-deploy-actions skill (bannzai/castle。private リポジトリ) 側へ `signing-assets.sh` のサブコマンドとして取り込む予定で、取り込み後は同 skill の手順を正とする

### provisioning profile を発行する

profile は app 本体と 2 つの extension の 3 本を発行する。profile 名は `project.pbxproj` の `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]` と workflow の ExportOptions に一致させる。

```sh
CERT_ID=68L9PY6PX2   # list-certificates で使う証明書の ID に置き換える

bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-profile \
  --name "Alarmify.AppStore" --bundle-id "com.bannzai.Alarmify" \
  --certificate-id "$CERT_ID" --out ./tmp/signing \
  --entitlements Alarmify/Alarmify.entitlements

bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-profile \
  --name "Alarmify.NotificationService.AppStore" --bundle-id "com.bannzai.Alarmify.NotificationService" \
  --certificate-id "$CERT_ID" --out ./tmp/signing \
  --entitlements AlarmifyNotificationService/AlarmifyNotificationService.entitlements

bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-profile \
  --name "Alarmify.Widget.AppStore" --bundle-id "com.bannzai.Alarmify.Widget" \
  --certificate-id "$CERT_ID" --out ./tmp/signing \
  --entitlements AlarmifyWidget/AlarmifyWidget.entitlements
```

`entitlements-check=missing` が出たら App ID 側の Capability が entitlements に足りていない。App Group (`com.apple.security.application-groups`) と Push Notifications (`aps-environment`) を Developer Portal で有効化し、`--recreate` を付けて発行し直して `entitlements-check=ok` にする。

**profile の再発行は 3 本セットで行う**。workflow は 3 本すべての Secret が非空であることを前提にしているため、app 本体だけ発行し直すと extension の profile が古いまま残り、次の archive が失敗する。

`.p12` とパスワードの原本はリポジトリにコミットせず、保管先を env-secret-registry skill の `secret-locations.tsv` に記録する。

## Secrets を登録する

配布の資格情報は environment `ios-deploy` の environment secrets に置き、デプロイできるブランチを `main` だけに絞る (workflow_dispatch は任意の branch を `--ref` に指定できるため、feature branch から本番の証明書を使う経路をここで塞ぐ)。environment とブランチ制限は適用済みで、再実行しても同じ状態に収束する。

```sh
# 適用済み (再実行しても同じ状態になる)
bash ~/.agents/skills/ios-deploy-actions/scripts/setup-environment.sh \
  --repo bannzai/Alarmify --environment ios-deploy --branch main

bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/Alarmify --env ios-deploy --dry-run \
  --secret ASC_API_KEY_ID="$ASC_API_KEY_ID" \
  --secret ASC_API_KEY_ISSUER_ID="$ASC_API_KEY_ISSUER_ID" \
  --secret ASC_API_KEY_P8_BASE64="$ASC_API_KEY_P8_BASE64" \
  --secret APPLE_DEVELOPMENT_TEAM_ID="$FASTLANE_TEAM_ID" \
  --secret-base64-file IOS_P12_CERTIFICATE_BASE64=./tmp/signing/distribution.p12 \
  --secret-from-file IOS_P12_PASSWORD=./tmp/signing/p12-password.txt \
  --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=./tmp/signing/Alarmify_AppStore.mobileprovision \
  --secret-base64-file IOS_NOTIFICATION_SERVICE_PROVISIONING_PROFILE_BASE64=./tmp/signing/Alarmify_NotificationService_AppStore.mobileprovision \
  --secret-base64-file IOS_WIDGET_PROVISIONING_PROFILE_BASE64=./tmp/signing/Alarmify_Widget_AppStore.mobileprovision \
  --secret REVENUECAT_API_KEY="$REVENUECAT_API_KEY"
```

`REVENUECAT_API_KEY` は RevenueCat の App Store 用 public API key (`appl_` で始まる)。Release ビルドの Build Phase (`scripts/check_release_revenuecat_key.sh`) が `appl_` のキーを要求し、無いと archive が失敗する (Test Store のキー入りバイナリを出荷しないため)。ローカルは gitignore した `Config.local.xcconfig`、CI はこの secret から `xcodebuild` の引数で渡す (取得方法は `Config.xcconfig` のコメント)。

`APPLE_DEVELOPMENT_TEAM_ID` は Developer Portal の Team ID。public リポジトリに Team ID の実値をコミットしない方針 (AGENTS.md「秘匿情報」) のため、workflow にベタ書きせず environment secret から渡す。ローカルでは direnv の `.envrc` の `FASTLANE_TEAM_ID` に入っている。

`--dry-run` で対象と値の非空を確認してから、`--dry-run` を外して登録する。1 つでも空値・不存在があれば 1 件も書き込まれない。登録後は `gh secret list --repo bannzai/Alarmify` を確認し、同じキーがリポジトリスコープに残っていないこと (environment 側にだけあること) を確かめる。

## 配布する

`main` へのマージで自動起動する (初回配布 https://github.com/bannzai/Alarmify/actions/runs/33865771891 の成功後、2026-09-04 に push トリガを有効にした)。起動した run の確認と、配布し直す時の手動起動は次のとおり。environment のブランチ制限があるため `--ref` は `main` にする。

```sh
gh run list --workflow ios-deploy.yml --limit 5
# 手動で配布し直す
gh workflow run ios-deploy.yml --ref main
RUN_ID="$(gh run list --workflow ios-deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID"
```

アップロード後、TestFlight の処理完了 (`processingState` が `PROCESSING` → `VALID`) を確認する。

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/asc-api.sh GET \
  "/v1/builds?filter[app]=<アプリの ID>&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate"
```

配布は同時に 1 本だけ実行できる。先行の run が未完了のまま dispatch すると、最初の step (Reject concurrent dispatch) で失敗する。完了を待ってから dispatch し直す。

## ビルド番号

ビルド番号 (`CURRENT_PROJECT_VERSION`) は `github.run_number + BUILD_NUMBER_OFFSET` で決まる。TestFlight に存在する最大のビルド番号は **2** (2026-09-04 の初回配布、`run_number` = 2。build 1 は検証エラーで未アップロード)。`run_number` は同じ workflow の run ごとに増え、次の run は 3 以上になるため、offset は `0` のままで単調増加が保たれる。App Store Connect のビルド番号は同一バージョン内で単調増加が必要なので、workflow を作り直す・名前を変える等で `run_number` が 1 から数え直される場合は、その時点の TestFlight の最大ビルド番号 (`asc-api.sh GET "/v1/builds?filter[app]=6808548984&sort=-version&limit=1&fields[builds]=version"`) 以上を offset にする。

## Re-run の可否

- **Upload to TestFlight まで進んで失敗した run は Re-run しない**。Re-run では `run_number` が変わらず同じビルド番号になり、アップロード済みと同じ番号の再送は重複として拒否される。原因を直して新しく dispatch する
- Upload より前の step で失敗した run は、その番号がまだアップロードされていないため Re-run で復旧してよい

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-12
claude --resume 0578bd60-8548-49a9-a76b-62987bb07c49
```
