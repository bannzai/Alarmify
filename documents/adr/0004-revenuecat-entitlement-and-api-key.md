# 0004. 課金は RevenueCat で行い、API キーは xcconfig 経由で渡す

## Status
Accepted (2026-09-02)

## Context
Alarmify の課金設計は Freemium + サブスクリプション (`documents/PROJECT.md`) で、無料枠の上限判定はサーバー側 (#2) が持つ。iOS 側には「購入・復元」と「今このユーザーが Pro かどうか」の判定が要る。

判定の参照元には 2 つの選択肢がある。1 つは参照のたびに SDK へ問い合わせる方法で、View 以外 (push 受信後の処理・App Intent 等) から同期的に参照できない。もう 1 つは判定結果をローカルにキャッシュする方法で、同期参照できる代わりに、アプリを閉じている間に購読が失効・返金された時に古い判定が残る。

API キーの扱いにも制約がある。本リポジトリは public のため、App Store 用の public API key (`appl_`) をソースやプロジェクト設定にコミットできない。一方でキーが無いビルド (CI・コントリビューターの手元) もビルドが通る必要がある。

## Decision
課金は RevenueCat SDK (`purchases-ios-spm`) で行い、entitlement `pro` の判定を UserDefaults にキャッシュする。キャッシュには失効日時と、RevenueCat がその判定を行った時刻 (`CustomerInfo.requestDate`) も併せて保存し、参照時に `cachedProActive(active:expirationDate:evaluatedAt:now:)` で現在時刻と突き合わせて判定する。失効日時を過ぎていても、RevenueCat が失効日時以降に有効と判定していた場合 (Apple の請求猶予期間など、RevenueCat 側が正を持つ延長) はその判定を尊重して有効のままにする。RevenueCat の公式ドキュメントは猶予期間中の `expirationDate` の扱いを明記していないため、失効日時だけで無効に倒さない。キャッシュの更新は `customerInfoStream` の監視・購入直後・復元直後の 3 経路すべてで `ProEntitlement.cacheEntitlement(customerInfo:)` に集約する。

API キーは `Config.xcconfig` の `REVENUECAT_API_KEY` を Info.plist の `RevenueCatAPIKey` へ流し込み、`ProEntitlement.revenueCatAPIKey` が読み取る。実キーは gitignore した `Config.local.xcconfig` で上書きする。キーが空の環境では `Purchases.configure` を呼ばず、ペイウォールは価格を表示せずに再読み込みの導線を出す。Release ビルドで `appl_` 以外のキーだった場合は `scripts/check_release_revenuecat_key.sh` がビルドを失敗させる。

ローカルの課金検証は StoreKit Configuration file (`Alarmify.storekit`) と `SKTestSession` で行い、App Store Connect・ネットワークに触れずに商品解決と購入を検証できるようにする。`.storekit` はテストバンドルの資源としてだけ使い、共有 scheme の Run には設定しない。scheme で設定するとローカル生成のトランザクションになり、`appl_` キーで RevenueCat を通した実ストア (sandbox) の購入を検証できなくなるため。

## Consequences

**良い点:**
- entitlement を View 以外からも同期参照できる。失効日時を併せて持つため、アプリ停止中の失効で古い `true` を返し続けることがない
- 実キーをコミットせずに済み、キーを持たない環境でもビルド・テストが通る。出荷ビルドのキー取り違えはビルドエラーで気づける
- 商品識別子・価格・購読期間の取り違えを `xcodebuild test` だけで検出できる

**悪い点 / 引き受けるリスク:**
- キャッシュはあくまで最後に観測した RevenueCat の状態で、サーバー側の無料枠判定 (#2) との整合は別途 entitlement をバックエンドへ連携して取る必要がある
- アプリを閉じている間に失効し、その後に請求猶予期間へ入った場合は、次に RevenueCat と同期するまで無効 (Free) として扱う (オフラインでは無効側に倒す)
- キーが空の環境ではペイウォールの購入導線を一切表示できないため、購入フローの検証には Test Store か実ストアのキーが要る
- StoreKit Testing は simulator の runtime に依存する。iOS 26.5 の simulator では `xcodebuild test` 経由で機能しないため、該当 runtime ではテストを skip する
