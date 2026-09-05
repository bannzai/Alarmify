# 0005. サーバー側のプランは RevenueCat の webhook で更新する

## Status
Accepted (2026-09-04)

## Context
無料枠の上限 (API トークン 1 つ・月 20 件のアラーム) はサーバー (`functions/src/lib/plan.ts`) が `users/{uid}.plan` を見て判定する。iOS 側は RevenueCat の entitlement `pro` を UserDefaults にキャッシュして表示に使う ([ADR 0004](0004-revenuecat-entitlement-and-api-key.md)) が、この時点では `plan` を更新する経路が無く、購入しても上限が解除されなかった (#19)。

`plan` の更新元には 2 つの選択肢があった。

1. RevenueCat の webhook を Cloud Functions で受け、イベントの app_user_id を uid として `plan` を書く
2. アプリが `customerInfoStream` の更新をアプリ向け API へ送り、サーバーが `plan` を書く

2 はアプリを開かない間の更新・失効に追従できない。年額の購読者がアプリを開かずに Webhook だけ使い続けると、更新後もサーバー側は失効扱いのままになる。また、アプリからの申告をそのまま信じるとサーバーの上限判定を迂回できるため、サーバーが RevenueCat へ問い合わせて検証する必要があり、結局 RevenueCat との連携が要る。

1 は端末の状態に依存せず、RevenueCat が正を持つ購読の状態変化 (更新・停止・失効・返金・請求エラー・端末間の引き継ぎ) をそのままサーバーへ運ぶ。webhook は Dashboard で URL と Authorization ヘッダーを設定するだけで、追加の API キーを Functions に持たなくてよい。

## Decision
方式 1 を採る。Functions `revenueCatWebhook` (`functions/src/api/revenueCatWebhook.ts`) が RevenueCat の webhook を受け、次の規則で `users/{uid}` を更新する (判定の本体は `functions/src/lib/revenueCat.ts` の純粋関数)。

- **uid の解決**: アプリは匿名認証の完了後に `Purchases.logIn(uid)` を呼ぶ (`ProEntitlement.logIn`)。webhook の `app_user_id` が uid になるため、それをそのまま使う。匿名 ID (`$RCAnonymousID:`) しか無いイベントは結び付ける相手がいないので無視する。接続先がエミュレータのアカウントは `logIn` せず、残っている本番の identity は `logOut` で匿名に戻す (webhook は本番の Firestore にしか届かず、本番に存在しない uid のドキュメントを作らない・本番の uid での購入を起こさないため)。ペイウォールの購入・復元は結び付けが成立してから始め、接続先がエミュレータの間は行えない (`AccountSession.purchaseLinkState`。起動時の `logIn` が失敗したまま匿名 ID で購入すると webhook に uid が載らず、エミュレータで匿名 ID のまま購入すると本番へ戻した起動の `logIn` で本番の uid にマージされてしまうため)
- **削除済みアカウントの扱い**: ユーザーのドキュメントが無い uid を pro にする時は、Firebase Auth にユーザーが今も存在する場合だけ作る。削除の目印 (`deletedAccounts/{uid}`) は 2 時間で消えるため、削除後に RevenueCat 側へ残った購読の RENEWAL が削除済みアカウントのドキュメントを作り直さないようにする
- **プランの判定**: `entitlement_ids` に `pro` を含むイベントを、その時点の失効日時 (`expiration_at_ms`。請求猶予期間中は `grace_period_expiration_at_ms` が後ならそちら) つきの pro として保存する。失効日時が過去なら free。イベント種別ごとの分岐は持たない (CANCELLATION は失効日時まで pro のまま、EXPIRATION と返金は失効日時が過去になるので free)。TRANSFER は失う側を free、受け取る側を期限なしの pro にする
- **読み取り時の再判定**: 上限の判定は保存した `plan` をそのまま使わず、`effectivePlan(user, now)` で `proExpiresAt` と現在時刻を突き合わせる。失効の webhook が遅れても、失効日時を過ぎた pro に上限の解除を続けない
- **順序と再送**: 保存した `planEventAt` より古いイベントは無視し、同じイベントの再送は同じ状態に収束させる (冪等)
- **認証**: Dashboard に設定した Authorization ヘッダーの値と Secret `REVENUECAT_WEBHOOK_AUTHORIZATION` の一致だけで認証する (App Check の対象外)。設定手順は `documents/revenuecat-webhook.md`
- **アプリ側**: 上限で拒否された応答 (`plan_limit_exceeded`) を API トークン画面が受け取ってペイウォールを開く。アプリはプランを申告しない

`Purchases.logIn` で uid を連携するため、App Privacy の PURCHASE_HISTORY は DATA_LINKED_TO_YOU にする (`documents/app-privacy.md`)。

## Consequences

**良い点:**
- 端末が起動していなくても、購読の更新・失効・返金がサーバーの上限判定に反映される
- サーバーはアプリからの申告を一切信じない。上限判定の迂回には RevenueCat の webhook の Authorization ヘッダーの値が要る
- 判定が純粋関数で、エミュレータのテストで購入から上限解除までを再現できる

**悪い点 / 引き受けるリスク:**
- 購入からサーバーのプラン更新までに webhook の到着分 (通常は数秒) の遅れがある。RevenueCat の配送は 2xx 以外で最大 5 回 (5・10・20・40・80 分後) の再送で、それでも届かなければサーバー側は古い状態のまま次のイベントを待つ。失効側は `proExpiresAt` の再判定で守られるが、更新 (RENEWAL) の取りこぼしは失効日時を過ぎた時点で free に落ちる
- TRANSFER で entitlement を受け取った側は失効日時が分からず期限なしの pro になる。その後の RENEWAL / EXPIRATION が届くまで、失効しても pro のまま残り得る
- イベントは購読 1 件ごとで、同じ entitlement を与える購読を複数持つ利用者では、後に届いたイベントの失効日時で上書きされる
- Secret `REVENUECAT_WEBHOOK_AUTHORIZATION` が Secret Manager に無いと `firebase deploy` が Functions 全体で止まる (defineSecret の仕様)。Dashboard 側の webhook 設定と合わせて、本番の有効化は Web UI を伴う手作業になる
- RevenueCat の Dashboard 設定 (webhook の URL・ヘッダー・環境フィルタ) はリポジトリ管理外で、変更履歴が残らない
