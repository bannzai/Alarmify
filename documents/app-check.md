# Firebase App Check (アプリ → バックエンドの Functions を保護する)

アプリ向けの Functions (`appApi` と Callable `deleteAccount`) を Firebase App Check で保護し、アプリ以外からの呼び出しを拒否する ([ADR 0001](adr/0001-firebase-backend.md))。外部サービス向けの `alarmsApi` は任意のサーバーから呼ばれる前提のため対象外で、API トークン + レート制限で守る。

導入は firebase-app-check-setup skill (bannzai/castle) の手順に沿う。本書はこのプロジェクトでの構成・現在の適用段階・切り替え手順を記録する。

## 構成

| 層 | 実装 | 備考 |
| --- | --- | --- |
| iOS (クライアント) | `Alarmify/Utils/AppCheckProviderFactory.swift` を `FirebaseApp.configure()` より前に登録する (`Alarmify/Utils/AppDelegate.swift`)。simulator はデバッグプロバイダ、実機は App Attest | `Alarmify/Alarmify.entitlements` の `com.apple.developer.devicecheck.appattest-environment` は `production` (App Check は App Attest の sandbox 環境のトークンを受け付けない。TestFlight / App Store 配布では entitlement の値に関わらず production が使われる) |
| iOS (送信) | `URLSessionAlarmifyAPIClient` が `AppCheck.appCheck().token(forcingRefresh:)` で得たトークンを `X-Firebase-AppCheck` ヘッダーに付ける | トークンを取得できない時はヘッダー無しで送り、扱いはサーバーの適用段階に委ねる (クライアントで止めると監視段階の利用まで止まる) |
| Functions (`appApi`) | `functions/src/lib/appCheck.ts` の `requireAppCheck` を ID トークン検証より前に通す。`firebase-admin` の `getAppCheck().verifyToken` で検証する | 適用段階は環境変数 `ALARMIFY_APP_CHECK_ENFORCEMENT` (`monitor` / `enforce`。未設定は `monitor`) |
| Functions (`deleteAccount`) | `onCall({ enforceAppCheck })` を同じ環境変数から決める | Callable のオプションはデプロイ時に決まるため、切り替えには再デプロイが要る |
| Firebase (`alarmify-prod`) | App Check API の有効化、iOS アプリの Team ID、App Attest プロバイダ、simulator 用デバッグトークンの登録 | 下記「Firebase 側の登録」。skill の `firebase-app-check-api.sh setup-ios` で行う |
| Apple Developer | App ID `com.bannzai.Alarmify` の App Attest capability | 2026-09-04 に有効化済み (下記「Apple 側の設定」) |

適用段階ごとのサーバーの挙動:

| `ALARMIFY_APP_CHECK_ENFORCEMENT` | ヘッダー無し | 検証失敗 | 検証成功 |
| --- | --- | --- | --- |
| `monitor` (監視のみ) | 通す。warn ログ `app check token missing` | 通す。warn ログ `app check token invalid` | 通す |
| `enforce` (強制) | 401 `app_check_required` | 401 `app_check_invalid` | 通す |

`deleteAccount` (Callable) は firebase-functions の実装に従い、`monitor` では検証失敗を `Failed to validate AppCheck token.` の warn ログに残して通し、`enforce` では 401 を返す。

値の置き場所は `functions/.env.alarmify-prod` (firebase-tools が `functions/.env.<project id>` をデプロイ時に読み込む: https://firebase.google.com/docs/functions/config-env )。監視のみの間はこのファイルを置かず、環境変数が無い時のコードの既定値 (`monitor`) で動かす。ローカルのエミュレータ (`demo-alarmify`) はこのファイルを読まないため常に既定値で動き、強制の挙動を手で確かめる時は起動時に環境変数を渡す (下記「ローカルでの確認」)。

agent (Claude Code / Codex) の permissions は `.env*` の読み書きを deny しているため、このファイルの作成・編集は bannzai が行う。

## 現在の適用段階

| 日付 | 段階 | 内容 |
| --- | --- | --- |
| 2026-09-04 | 監視のみ (`monitor`) | クライアント実装と Functions の検証を追加。Apple の App Attest capability を有効化。Firebase 側の登録 (App Check API の有効化・Team ID・App Attest プロバイダ・デバッグトークン `simtunnel alarmify`) を `setup-ios --apply` で実施。provisioning profile の再生成は未実施 (bannzai がやる作業の一覧 https://github.com/bannzai/Alarmify/issues/25 ) |

強制 (`enforce`) への切り替えは公開前チェックリスト ( https://github.com/bannzai/Alarmify/issues/14 ) の項目として扱う。

## 監視のみ → 強制への切り替え手順

1. **前提を揃える**: 下記「Firebase 側の登録」と「Apple 側の設定」がすべて完了していること。未完了のまま強制に切り替えると、実機の App Attest とsimulator のデバッグプロバイダの両方がトークンを得られず、アプリからの呼び出しが全部 401 になる
2. **監視ログで未検証リクエストが残っていないことを確認する** (直近 7 日)。新クライアントを配布した後、正当なクライアント (TestFlight の実機と、デバッグトークンを渡した simulator) からのリクエストで下記のログが出なくなっていることを見る

   ```sh
   gcloud logging read \
     'resource.type="cloud_run_revision" AND resource.labels.service_name="appapi" AND jsonPayload.message=~"^app check token"' \
     --project alarmify-prod --freshness=7d --limit 50 --format='table(timestamp,jsonPayload.message,jsonPayload.path)'
   # Callable (deleteAccount) 側の検証失敗
   gcloud logging read \
     'resource.type="cloud_run_revision" AND resource.labels.service_name="deleteaccount" AND textPayload:"AppCheck"' \
     --project alarmify-prod --freshness=7d --limit 50
   ```

3. **`functions/.env.alarmify-prod` を作成して PR を作り、main へマージする** (agent は `.env*` を書けないため bannzai が作る。値をコミットするのは、以降のどの経路のデプロイでも段階が保たれるようにするため)

   ```sh
   cat > functions/.env.alarmify-prod <<'EOF'
   # Firebase App Check の適用段階。monitor = 未検証リクエストを warn ログに残して通す / enforce = 401 で拒否する。
   # 切り替え手順は documents/app-check.md。値を変えたら appApi と deleteAccount を再デプロイする
   ALARMIFY_APP_CHECK_ENFORCEMENT=enforce
   EOF
   ```

4. **`appApi` と `deleteAccount` を再デプロイする** (`documents/functions-deploy.md`)

   ```sh
   gh workflow run functions-deploy.yml --ref main -f environment=prod -f functions=appApi,deleteAccount
   # ローカルから行う場合
   make deploy-functions FUNCTIONS=appApi,deleteAccount
   ```

5. **切り替わったことを確認する**: トークン無しの curl が 401 `app_check_required` を返し、デバッグトークンを渡した simulator (simtunnel) から API トークン画面の発行・失効が通ること

   ```sh
   curl -i -X POST https://asia-northeast1-alarmify-prod.cloudfunctions.net/appApi/v1/devices \
     -H 'Content-Type: application/json' -d '{}'
   # → HTTP 401、body の error.code が app_check_required
   ```

6. 本書の「現在の適用段階」に日付と段階を追記する

**戻し方**: `functions/.env.alarmify-prod` を `ALARMIFY_APP_CHECK_ENFORCEMENT=monitor` に書き換える (またはファイルを消す) をマージして、同じ 2 関数を再デプロイする。正当な通信が拒否されている場合はまずこれで復旧し、原因 (プロバイダ登録・profile の entitlement・デバッグトークンの失効) を調べる。

Firebase Console / App Check API の「サービスの強制適用」(`firebase-app-check-api.sh set-enforcement`) は Firestore 等の Firebase 標準サービス向けの設定で、Functions には効かない。このアプリはクライアントから Firestore を直接読み書きしない (`firestore.rules` は全パス deny) ため、標準サービス側の強制適用は行わない。

## Firebase 側の登録

Firebase の外部状態を変える操作のため、firebase-app-check-setup skill は `--apply` の前に対象 (project / app ID / Team ID / デバッグトークンの保存先) の確認を求める。2026-09-04 に bannzai の承認で `--apply` を実行済み (`team_id_updated` / `app_attest_configured` / `debug_token_created` がすべて true)。再実行しても同名のデバッグトークンは増えない。

```sh
# 計画の確認 (書き込まない)
bash ~/.claude/skills/firebase-app-check-setup/scripts/firebase-app-check-api.sh setup-ios \
  alarmify-prod 1:320409781062:ios:8ec4f1f6670fc725c81b47 "$FASTLANE_TEAM_ID" \
  "simtunnel alarmify" ~/.config/alarmify/appcheck-debug-token.uuid

# 適用 (App Check API の有効化・Team ID・App Attest プロバイダ・デバッグトークンの登録。再実行しても同名のトークンは増えない)
bash ~/.claude/skills/firebase-app-check-setup/scripts/firebase-app-check-api.sh setup-ios \
  alarmify-prod 1:320409781062:ios:8ec4f1f6670fc725c81b47 "$FASTLANE_TEAM_ID" \
  "simtunnel alarmify" ~/.config/alarmify/appcheck-debug-token.uuid --apply
```

- `1:320409781062:ios:8ec4f1f6670fc725c81b47` は `Alarmify/GoogleService-Info.plist` の `GOOGLE_APP_ID`。Team ID は direnv の `FASTLANE_TEAM_ID` から渡す (public リポジトリに実値を書かない)
- デバッグトークンは skill が UUID を生成して `~/.config/alarmify/appcheck-debug-token.uuid` (mode 600) に保存する。値をリポジトリ・issue・ログに書かない
- simtunnel から渡すには、ios-simulator skill の規約どおり `~/.config/alarmify/appcheck-debug-token-simtunnel.secret` に `FIRAAppCheckDebugToken=<上の UUID>` の 1 行を mode 600 で作る (同 skill Phase 1「App Check を使うアプリ」)。表示名 `simtunnel alarmify` は同 skill の `appcheck-debug-token.sh ensure alarmify alarmify-prod <GOOGLE_APP_ID>` の既定と揃えている

## デバッグトークンの受け渡し (simulator)

simulator ではデバッグプロバイダが動き、環境変数 `FIRAAppCheckDebugToken` の値を Firebase に登録済みのトークンとして使う。渡さない場合は SDK が UUID を生成してコンソールに出すが、Firebase に登録されていないトークンは交換に失敗し、リクエストはヘッダー無しで送られる (監視段階では通り、強制段階では 401)。

| 経路 | 渡し方 |
| --- | --- |
| simtunnel (既定の動作確認経路) | `bash ~/.claude/skills/ios-simulator/scripts/ios-wda.sh --session <セッション名> launch com.bannzai.Alarmify --env-file ~/.config/alarmify/appcheck-debug-token-simtunnel.secret` |
| ローカル sim-boot (`make ios`) | `SIMCTL_CHILD_FIRAAppCheckDebugToken="$(cat ~/.config/alarmify/appcheck-debug-token.uuid)" make ios` (`xcrun simctl launch` は `SIMCTL_CHILD_` 接頭辞の環境変数をアプリへ渡す) |
| ユニットテスト (`make test` / CI) | 不要。テストは App Check のトークン取得を行わない |

## Apple 側の設定

- **App Attest capability**: 2026-09-04 に ios-deploy-actions skill の `app-id-capabilities.sh enable --bundle-id com.bannzai.Alarmify --capability APP_ATTEST` で有効化した (App ID `S63PHTW726` の capability に `APP_ATTEST` が追加されたことを同スクリプトの `list` で確認)。firebase-app-check-setup skill の `appattest-capability.sh --apply` は公開 App Store Connect API (JWT) を使うが、同 API は `capabilityType` に `APP_ATTEST` を受け付けない (`ENTITY_ERROR.ATTRIBUTE.TYPE`、HTTP 409) ため、Apple ID の Web セッションを使う ios-deploy-actions 側のスクリプトで行った
- **provisioning profile の再生成**: Release の手動署名 (`Alarmify.AppStore`) は entitlement `com.apple.developer.devicecheck.appattest-environment` を含む profile が要る。capability を有効化する前に発行した現在の profile (ID `9YDV59L4TY`) には含まれないため、再生成して environment `ios-deploy` の secret `IOS_PROVISIONING_PROFILE_BASE64` を更新するまで `ios-deploy.yml` の archive は署名エラーで失敗する。再生成は profile の削除を伴うため bannzai の承認で実行する (issue #25)

  ```sh
  bash ~/.claude/skills/firebase-app-check-setup/scripts/appattest-profile.sh Alarmify.AppStore ./tmp/Alarmify.AppStore --yes
  bash ~/.claude/skills/firebase-app-check-setup/scripts/verify-profile-entitlement.sh ./tmp/Alarmify.AppStore.mobileprovision
  bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/Alarmify --env ios-deploy \
    --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=./tmp/Alarmify.AppStore.mobileprovision
  ```

  Extension (`Alarmify.NotificationService.AppStore` / `Alarmify.Widget.AppStore`) は App Check を呼ばず entitlement も変えないため再生成しない
- Debug (automatic signing) の実機ビルド (`make device`) は Xcode が profile を作り直すため作業不要

## ローカルでの確認 (エミュレータ)

`functions/test/alarmFlow.test.ts` が `enforce` / `monitor` の両方の挙動を検証する (`make test-functions`)。強制段階の curl を手で確かめる場合は、エミュレータに環境変数を渡して起動する。

```sh
ALARMIFY_APP_CHECK_ENFORCEMENT=enforce make emulators   # エミュレータは起動したシェルの環境変数を関数に渡す
# 別のターミナルで
curl -i -X POST http://127.0.0.1:5410/demo-alarmify/asia-northeast1/appApi/v1/devices \
  -H 'Content-Type: application/json' -d '{}'
# → HTTP 401、error.code = app_check_required (ID トークンの検証より前に落ちる)
curl -i -X POST http://127.0.0.1:5410/demo-alarmify/asia-northeast1/alarmsApi/v1/alarms \
  -H 'Content-Type: application/json' -d '{"fire_at":"2030-01-01T00:00:00Z","title":"test"}'
# → HTTP 401、error.code = unauthenticated (外部 API は App Check を要求しない)
```

simulator のデバッグプロバイダは本番 (`alarmify-prod`) の App Check API とトークンを交換するため、エミュレータを `demo-alarmify` で動かすと正規のトークンでも検証を通せない (aud の project が一致しない)。「simulator から強制段階の API が通る」ことをエミュレータで確かめるには、エミュレータを `--project alarmify-prod` で起動し (Firestore / Auth はエミュレータのまま。FCM 送信を伴う `alarmsApi` は呼ばない)、アプリ側の接続先 (`AlarmifyBackend.emulator` の `demo-alarmify` パス) を一時的に `alarmify-prod` に向けたビルドをローカル simulator に入れ、`SIMCTL_CHILD_FIRAAppCheckDebugToken` でデバッグトークンを渡して開発者メニューから接続先を emulator に切り替える。2026-09-04 にこの手順で、配送先の登録と API トークンの発行が `enforce` のエミュレータを通ることを確認した (PR #39)。App Check SDK は交換したトークンを 1 時間キャッシュするため、トークン無しの挙動を simulator で見る時はアプリを入れ直す。
