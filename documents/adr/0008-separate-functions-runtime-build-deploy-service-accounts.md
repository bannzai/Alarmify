# 0008. Functions の実行・ビルド・デプロイのサービスアカウントを分離し、実行 SA を明示したロールに絞る

## Status
Accepted (2026-09-14)

## Context
`alarmify-prod` の Functions (gen2) は 6 関数すべてが既定の Compute Engine サービスアカウント (`320409781062-compute@developer.gserviceaccount.com`) で実行・ビルドされ、その SA がプロジェクトの `roles/editor` を持っていた (#63 の点検、#66)。外部から誰でも叩ける `alarmsApi` を含むバックエンドで、ランタイムが Editor を持つと、コードの脆弱性がそのままプロジェクト全体の書き込み権限になる。GitHub Actions のデプロイ用 SA も `roles/firebase.admin` / `roles/secretmanager.admin` を持ち、デプロイに必要な範囲より広かった。

Cloud Audit Logs (2026-09-12 のデプロイ) と firebase-tools v15.30.0 のソースで必要権限を照合した結果 ( https://github.com/bannzai/Alarmify/issues/66#issuecomment-5654369992 )、実行時に要るのは Firestore の読み書き・FCM の送信・Auth の getUser / deleteUser・Secret の読み取りだけで、デプロイに要るのは Functions の作成 / 更新・invoker の設定・Scheduler ジョブの更新・プロジェクトと Secret の参照だけだった。

実行 SA を分ける方法には次の選択肢があった。

1. 実行専用 SA (`functions-runtime@alarmify-prod.iam.gserviceaccount.com`) をオーナーが作って必要なロールを付け、`setGlobalOptions({ serviceAccount })` で全関数に割り当てる
2. firebase-functions v7.3.0 / firebase-tools v15.23.0 の declarative security (`requiresRole("roles/datastore.user")` 等) で、CLI に管理 SA (`firebase-fn-<hash>@…`) の作成とロール付与を任せる
3. 既定の compute SA を使い続け、Editor だけを外して必要なロールを付け直す

2 は、登録時とロールの変更時にデプロイを実行する主体へ `resourcemanager.projects.setIamPolicy` と `iam.serviceAccounts.create` (プロジェクトの IAM 管理者相当) を要求する。デプロイ用 SA の権限を縮小する目的と逆行し、2026-07 のリリース後も管理 SA の掃除や etag の修正が続いている。3 は compute SA がビルド SA も兼ねる (firebase-tools からビルド SA を指定できず、組織が無いため既定を変える組織ポリシーも使えない) ため、実行とビルドの権限が同じ SA に混ざったままになる。

## Decision
方式 1 を採る。

- **実行**: `functions-runtime@alarmify-prod.iam.gserviceaccount.com`。プロジェクトに `roles/datastore.user`・`roles/firebasecloudmessaging.admin`・`roles/firebaseauth.admin`・`roles/logging.logWriter`・`roles/cloudtrace.agent`・`roles/eventarc.eventReceiver`、各 Secret に `roles/secretmanager.secretAccessor`。`firebase/functions/src/index.ts` の `setGlobalOptions` でメールアドレスを固定する (本番プロジェクトは 1 つ。`name@` の省略記法は firebase-tools が Secret の付与と Scheduler の OIDC に未展開のまま渡すため使わない)
- **ビルド**: 既定の compute SA のまま、`roles/cloudbuild.builds.builder` 等のビルド用ロールだけを残して Editor を外す
- **デプロイ**: `github-firebase-deployer` は `roles/cloudfunctions.admin` と `roles/cloudscheduler.admin` を維持し、`roles/firebase.admin` → `roles/firebase.viewer`、`roles/secretmanager.admin` → `roles/secretmanager.viewer` に縮小する。実行 SA への ActAs (`roles/iam.serviceAccountUser`) を追加する
- **適用順序**: 実行 SA の作成・付与 → 移行デプロイ → compute SA の Editor 除去 → deployer の縮小。順序を入れ替えない (実行 SA を移す前に Editor を外すと稼働中の関数が権限を失う)。手順と復旧コマンドは `documents/functions-deploy.md`

## Consequences

**良い点:**
- ランタイムの権限が Firestore / FCM / Auth / Secret の読み取りに閉じ、コードの脆弱性がプロジェクト全体の書き込みに広がらない
- 実行・ビルド・デプロイの権限が SA ごとに分かれ、監査ログで主体を区別できる
- デプロイ経路 (`firebase deploy --only functions`)・コード・テストの構成は変えない (`setGlobalOptions` の 1 オプションだけ)

**悪い点 / 引き受けるリスク:**
- Editor による暗黙の権限が無くなるため、新しい Secret の accessor 付与・新しい GCP API の有効化・実行時に要る新しいロール (Cloud Tasks 等) はデプロイではなくオーナーの `gcloud` で先に行う運用になる (deployer は viewer のため付与できない)
- bannzai/castle の firebase-functions-deploy-iam-setup skill は admin ロールを前提にしており、再実行すると縮小が巻き戻る。skill の追随 ( https://github.com/bannzai/castle/issues/1055 ) までは再実行しない
- 実行時の API 呼び出しは Data Access 監査ログが無効のためコードからの推定で、実機での push 受信とアカウント削除の確認は移行デプロイ後に行う (#14)
- 定期実行関数の実行 SA を変える移行デプロイでは firebase-tools が Cloud Run の invoker を付け替えるため、deployer に `roles/cloudfunctions.admin` (`run.services.setIamPolicy`) が要り続ける。`roles/cloudfunctions.developer` へは落とせない
