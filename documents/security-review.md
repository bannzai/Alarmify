# 公開前のセキュリティ点検

点検日: 2026-09-12 (JST)。対象: `41f8379cd66f0e7187cf204d94d98624de661211`、bannzai/Alarmify、Firebase / GCP `alarmify-prod` (asia-northeast1)。開発環境は `.firebaserc` の `demo-alarmify` エミュレータで、別のクラウド検証環境は定義されていない。

## 結論と点検の限界

Issue #63 のコード・設定点検と、指定の Claude Code `/security-review` を完了した。レビューで悪用可能性を高い確度 (8/10 以上) で確認した HIGH / MEDIUM の脆弱性は0件。これは脆弱性の不在や公開可否の全面保証ではない。下記の残課題・未検証範囲を含めて判断する。

秘密鍵・実運用の API トークンの混入は今回の走査で確認しなかった。ただしスキャナーの生の結果は NG で、テスト用文字列・公開済み Firebase キー・環境設定の検出を含む。iOS キーの bundle ID 制限は実設定で確認済み。初回点検では権限の広さ、依存の警告、Privacy Manifest、CI の参照固定を指摘した。Privacy と CI は別 PR で対応済み。依存は qs の解消後も上流の互換対応待ちが残る (#85)。IAM 縮小、App Check の強制適用判断、webhook の設定確認、実機確認は引き続き追跡する。

初回点検後、別セッションで #58 の本番デプロイが完了した。再照会で6関数の更新日時が 2026-09-12 11:56 UTC、App Check が monitor と確認した。配布コミットは `a0dceb218165f75fc195faa4bf31087ecbec9bce` (PR #79)。以下のコード・依存・IAM の初回点検結果は冒頭の対象コミット時点の記録であり、最新 main 全体を再走査した結果ではない。負荷試験・侵入試験・実機操作・本番への書き込み・デプロイ・権限変更は実施していない。

## 秘匿情報の走査

`pre-public-check.sh --repo bannzai/Alarmify` を check-only / 検証先へのトークン送信なし / 除外指定なしで実行した。gitleaks 8.30.1、trufflehog 3.97.4。両エンジンの実行時表示は最新。全体 exit 1。

| 対象 | 実際の検出と判定 |
| --- | --- |
| Git 全履歴 | gitleaks 7 件。`AlarmifyTests/APITokenTests.swift` 4 件、`AlarmifyTests/AlarmifyAPIClientTests.swift` 3 件。各コミットの `git show` で全件を照合し、固定の `alm_…` テスト用文字列と確認。実 API が要求する `alm_` + 43文字の形式を満たさず、実際の資格情報ではない |
| Git 全履歴 | trufflehog 2 件。`Alarmify/GoogleService-Info.plist` を GoogleGeminiAPIKey として検出。履歴と現在のキーが同一で、GCP の iOS key ともメモリ内で照合済み。Generative Language API は許可対象に無く、検出器名だけで Gemini 秘密鍵とは判定しない |
| 現在ツリー | 8 件。上記テストの内容4件、plist の内容2件、plist と `firebase/functions/.env.alarmify-prod` のファイル名確認2件。環境ファイルは App Check のモード指定だけで秘密値を含まない。plist の公開は ADR 0003 と AGENTS.md の明示承認済み。検出を隠すための ignore・除外・追跡解除はしていない |
| GitHub 防御 | public、secret scanning と push protection は enabled |
| PR / Issue | 本文・タイトル63件、Issueコメント98件、PRレビューコメント580件を走査し検出0件。実行時点の件数で、後から作成した本点検の Issue / PR は含まない |

元ログは作業ディレクトリの `tmp/pre-public-check.log` と `tmp/pre-public-check/run-KxKEZD/` にある。元レポート・GitHub本文キャッシュ・キー実値を公開物へ添付しない。検出値の有効性確認 API、ローテーション、履歴書き換えは行っていない。スキルの走査対象外 (レビューのサマリー本文、commit コメント、Discussions、Wiki) や未知形式の secret まで不在を保証しない。

## 指定セキュリティレビューの結果

ユーザーが公開済みコードの Anthropic への送信を明示承認したうえで、Claude Code の組み込み `/security-review` を実行した。途中の領域別エージェントは最終結果を返さなかったため、同じセッションを追加委譲なしで再開し、直接読解による最終結果を取得した。CLI は exit 0、JSON は `subtype=success` / `is_error=false` / 権限拒否0件。結果はローカルの `tmp/security-review-final.json` に保存した。

レビューは worktree `972b7008a470d71374376bea84079ff504aae551` と、開始時の origin/main `3efed353a469ba9418f9f35edd2bbcbbf433daf7` の公開コードを対象にした。main と異なるファイルは `git show` で読む方式で、実行中に共有の origin/main が更新されたため、全ファイルが単一コミットに固定されたレビューとは扱わない。本番の監視モードはレビューの自己申告ではなく、別途 GCP 再照会で確認した。

- 認証・トークン・所有者分離・入力検証・削除中の書き込み保護・webhook・開発者メニュー・workflow を確認し、判定基準を満たす HIGH / MEDIUM は0件。主要根拠の `verifyIdToken`、`timingSafeEqual`、`revokedAt`、削除中の目印とユーザー不在時の拒否を親セッションでもソースに照合した。
- App Check monitor、インスタンス内レート制限、IAM などの運用上の課題はレビューの「0件」に吸収せず、別途下記で追跡する。削除中の外部 API は目印を直接参照しないため、削除要求時点で全 API トークンが即時失効する保証はない。ユーザー文書が無い場合はアラーム作成を拒否し、削除途中の失敗は sweep の回復に依存する。
- 外部 title の LocalizationValue への変換は、自端末の表示に関する候補として除外。文字列の `%` を含む実機表示は未検証で、セキュリティ修正としては採用しない。
- Widget の UserDefaults 参照はレビューで未確認だったため追確認した。対象 main の Widget Sources は Widget本体・Bundle・AlarmifyAlarmMetadata・DesignTokens の4ファイルで、AppGroup / AlarmKitScheduler は所属せず、4ファイルにも UserDefaults 参照は無い。Widget の manifest 不足という指摘にはしない。提出 archive の集約は #14。
- 負荷・侵入・実機試験、サーバーログ全件、独立した複数エージェントのレビューは実施していない。IAM / GitHub environment / APIキー制限は以下の直接点検で補った。

## コード・設定の所見

| 観点 | 確認結果・根拠 | 残課題 |
| --- | --- | --- |
| 外部 API トークン | `lib/apiToken.ts` は32バイトの乱数を生成し、`api/appApi.ts` は SHA-256 と表示 prefix を保存して平文を発行時だけ返す。`lib/store.ts` は hash の collection group 検索を limit 2 に制限し、失効判定と `timingSafeEqual` で照合 | Firestore 検索を含む処理全体が定数時間という保証はない。固定長ハッシュの比較に対する対策として確認 |
| 外部 API のレート制限 | `api/externalApi.ts` は形式不正を DB 前で拒否。未確認トークンの共有枠はインスタンス毎600回/分、トークン別60回/分で、DB 参照前に消費。既知トークンは共有枠から外れる。`lib/rateLimit.ts` はメモリ内の固定ウィンドウでキー数上限あり | 複数インスタンス・再起動・ウィンドウ境界をまたぐ厳密な総量上限ではない。maxInstances=10 も費用の上限ではない。#62 で費用・流量の許容範囲と追加防御を評価 |
| 入力検証 | `schema/request.ts` の UUID 正規化、title 1〜200文字、暦日とタイムゾーンを含む日時検証、fire_at / fire_in の排他指定。`api/externalApi.ts` で絶対時刻の30秒以上先・365日以内を検査。JSON 32KB (webhook 64KB) | 静的点検。本番の悪意ある入力・負荷試験は未実施 |
| エラー応答 | `lib/errors.ts` は未知の内部例外を固定の500応答にし、JSON形式不正とサイズ超過も固定文言。外部 API の push 応答は成功/失敗件数のみ | サーバーログへ例外を出す経路は存在し、過去ログ全件の秘匿情報走査は対象外 |
| アプリ向け認証 | `index.ts` の Firebase Admin `verifyIdToken` で検証した uid を `api/appApi.ts` が採用。要求 body の uid を所有者として信用しない。ID トークン失効確認オプションは未指定 | 即時失効を保証せず、削除後は下記目印と有効期限を前提にする |
| App Check | 現在のソースは App Check → IDトークンの順で検証。`lib/appCheck.ts` は monitor / enforce を実装し、不明なモード値は monitor。初回の `.env.alarmify-prod` は enforce | PR #79 で monitor に変更し、本番6関数にも反映済みと再照会で確認。対象は `appApi` / `deleteAccount`。外部サービス向け `alarmsApi` は API トークン、RevenueCat は webhook Authorization で認証し、App Check の対象外。強制適用は #14 の観測後の判断 |
| 削除中の保護 | `api/appApi.ts` は端末登録・トークン発行・端末反映結果の書き込みトランザクションで `deletedAccounts/{uid}` を読み、410で拒否。削除目印は最低2時間保持 | #58 で本番反映済み。競合テストは PR #77 で修正。別セッションの検証結果であり、この点検で削除操作は実行していない |
| Callable deleteAccount | `account/deleteAccount.ts` は request.auth.uid だけを削除対象にする。認証なしは拒否し、削除の失敗を sweep で回復する。`index.ts` の enforceAppCheck は配置時のモードに連動 | 実際のアカウント削除は点検で実行しない。App Check は #58 で monitor として配置済み |
| RevenueCat webhook | Authorization が空・不一致なら拒否。等長バッファは `timingSafeEqual`、異長は即拒否なので「長さを含む完全な定数時間」ではない。古いイベント・削除中/削除済みユーザーへの再作成を防ぐ処理あり | `REVENUECAT_WEBHOOK_AUTHORIZATION` の Secret 名は初回から存在した。関数は初回に無かったが、#58 完了後の再照会では配置済み。Secret の値や Dashboard との一致は未確認。#25 |
| Firestore | ローカルの全パス deny と、Firebase Rules API から取得した実配置のルールが一致。実配置の更新日時は 2026-09-03T04:07:04Z。インデックス定義は検索設定で認可の許可ではない | Admin SDK はルールの代わりに IAM とアプリの認可に依存。IAM は #66 |
| 開発者メニュー | `Alarmify/Debug/DeveloperSettings.swift` は DEBUG または sandboxReceipt で解放。App Store の通常経路では保存値を無視して本番設定を返し、設定の保存も拒否 | 静的判定のみ。TestFlight / App Store の配布ビルド確認は #14。クライアント改変に対するサーバー認可の代わりにはしない |
| Firebase iOS API キー | plist と GCP の iOS key が一致し、allowedBundleIds は `com.bannzai.Alarmify`。API allowlist は Firebase 関連27サービスで Generative Language API は含まない | ADR 0003 の bundle ID 制限は確認済みで変更不要。キーや bundle ID 自体を利用者認証と見なさない |
| Privacy Manifest / App Privacy | app は UserID / DeviceID / OtherUserContent、JSON はこれらと PurchaseHistory を宣言し、trackingなし・linkedあり。Notification Service Extension は共有コード経由で UserDefaults を使うが Resources フェーズと manifest が無い | #64 に実装と文書の不一致を追記済み。SDK 同梱 manifest・提出 archive 集約・ASC 再取得の整合は #64 で実施 |

Functions のファイル名は `firebase/functions/src/` を基点とする。

## インフラと資格情報

- 初回点検時の Cloud Run の全5サービスは ingress=ALLOW_ALL。`alarmsapi` / `appapi` / `deleteaccount` は allUsers の run.invoker があり、アプリケーション内の認証を入口にする構成。定期処理2サービスは実行用 SA の run.invoker のみで、allUsers は無い。Scheduler は両方 ENABLED で OIDC の SA 指定あり。
- 初回点検時の実行 SA は5関数とも既定 Compute Engine SA。そのプロジェクト権限に Editor、Cloud Build、Artifact Registry の権限が混在。デプロイ SA も cloudfunctions.admin / firebase.admin / cloudscheduler.admin / secretmanager.admin をプロジェクト単位で保持。最小権限とは判定しない (#66)。親階層の継承 IAM と全 Secret 個別 IAM までは棚卸ししていない。
- GitHub の firebase-prod / ios-deploy environment は実 API で main ブランチのみを許可。required reviewer は無く admins bypass は許可されている。配布 workflow の permissions は contents: read / actions: read。環境の SA 鍵・署名・ASC・RevenueCat の Secrets は名前だけ確認し、値は取得していない。repository Secrets は Tailscale OIDC 関連2名で、配布用資格情報は environment 側にある。
- 配布 workflow は action をフル SHA 固定、Functions では依存インストール後に SA 鍵を復元し、終了時に除去する構成。通常 CI の4箇所は可変タグ (#68)。GitHub の allowed_actions=all / sha_pinning_required=false は組織的な強制ではなくコード規約で固定する現状として記録する。

## 依存の既知脆弱性

| 検査 | 結果 |
| --- | --- |
| `npm --prefix firebase/functions audit --json` | exit 1。moderate 10パッケージ、high / critical 0。firebase-tools に至る開発依存の経路。OpenTelemetry Core、csv-parse、qs (2件)、stream-json の advisory が起点で、10は独立した脆弱性数ではない。#67 |
| `npm --prefix firebase/functions audit --omit=dev --json` | exit 0。検出0 |
| SwiftPM | Package.resolved の15リビジョンを OSV querybatch の commit 検索で照合し、全件空の結果。記録は `tmp/spm-osv.json`。登録済み advisory との一致が無いという意味で、SwiftPM 全体やバイナリ内依存の脆弱性不在を保証しない |

初回後の PR #72 は qs を解消したが、全警告の解消ではない。同 PR の記録では開発依存 moderate 5パッケージが残り、理由は `documents/npm-audit.md` にある。最終 push 時の警告を受けて GitHub API を再照会し、csv-parse (alert 14 / GHSA-8cw4-87c7-c6xx) と stream-json (alert 13 / GHSA-528h-pc64-c93x) の2件が open / medium と確認した。OpenTelemetry Core を含む CLI の残件と再確認条件は #85 で追跡する。

依存更新は今回行っていない。コード変更なしの監査文書であり、ビルド・ユニットテスト・シミュレータは実行していない。#58 の別セッションでのテスト結果を今回の実行成功として扱わない。

## 指摘の対応状況と追跡先

初回点検後、PR #69 (CI 固定)、#70 (Privacy)、#72 (開発依存)、#75 (費用試算)、#77 / #79 (テスト・本番配置) のマージと各 Issue の close を GitHub で確認した。以下では初回の指摘と現在の追跡先を分けて記録する。各 PR の検証は別セッションによるもので、この点検の再実行結果ではない。

| 対応 | Issue |
| --- | --- |
| 完了: 指定の Claude セキュリティレビューと結果の記録 | #63。#25 の承認待ちは解消済み |
| 完了: 最新 Functions・webhook の配置、App Check monitor、競合テストの解消 (PR #77 / #79)。強制適用の判断は #14 | https://github.com/bannzai/Alarmify/issues/58 |
| webhook Dashboard の設定 | https://github.com/bannzai/Alarmify/issues/25 |
| 費用試算・上限評価は完了 (PR #75)。残る通知連携・保持期間掃除の容量は #73 / #74 | https://github.com/bannzai/Alarmify/issues/62 |
| 対応済み: Manifest の不足・App Group の理由・ASC 回答 (PR #70)。提出 archive の集約確認は #14 | https://github.com/bannzai/Alarmify/issues/64 |
| 実行・ビルド・デプロイ IAM の縮小 | https://github.com/bannzai/Alarmify/issues/66 |
| 一部対応: PR #72 で qs を解消。CLI の残件は上流の互換対応待ち | https://github.com/bannzai/Alarmify/issues/85 |
| 対応済み: CI action の SHA 固定 (PR #69) | https://github.com/bannzai/Alarmify/issues/68 |
| 配布ビルドの実機確認 | https://github.com/bannzai/Alarmify/issues/14 |

## 参照した一次資料

- Firebase API キーの公開と制限: https://firebase.google.com/docs/projects/api-keys
- Required Reason API: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- OSV の commit 照合: https://google.github.io/osv.dev/post-v1-querybatch/
- Claude の組み込みコマンド: https://code.claude.com/docs/en/commands

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-63
codex resume 01a09526-cdc9-7343-8c0a-ed3fbb3da65f
```
