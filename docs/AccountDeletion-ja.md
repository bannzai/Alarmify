# アカウントとデータの削除方法

Signalarm（提供者: bannzai）のアカウントと、提供者のサーバーに保存されたデータを削除する手順です。

## アプリ内から削除する

1. Signalarm を開き、「設定」を開きます
2. 「アカウントを削除」を選びます
3. 確認画面で削除を実行します
4. Sign in with Apple を連携している場合は、削除の前に Sign in with Apple の認証を求められます。認証すると、Apple のトークンを失効させてからアカウントを削除します。認証の画面を閉じた場合や、トークンの失効に失敗した場合、アカウントは削除されません<!-- source: Alarmify/Account/AccountSession.swift: deleteAccount() は appleIDLinked なら revokeAppleToken() (Sign in with Apple をやり直して authorization code を受け取り Auth.auth().revokeToken(withAuthorizationCode:)) を済ませてから apiClient.deleteAccount() を呼び、失効に失敗したらエラーを投げて削除に進まない。Alarmify/Settings/SettingsView.swift: シートを閉じた ASAuthorizationError.canceled は削除をやめたものとして扱う -->

削除は即時に実行され、取り消せません。

## メールで削除を依頼する

アプリを利用できない場合は、bannzai.app@gmail.com 宛に「アカウント削除希望」と、アプリの設定画面に表示されるアカウント ID を記載してお送りください。ご本人であることを確認の上、7 日以内に削除します。

## 削除されるデータ

- アカウント識別子（匿名ユーザー ID、または Sign in with Apple を連携した場合のユーザー ID。連携している Apple のトークンは失効させます）
- 発行済みの API トークン（削除後は外部サービスからの呼び出しがすべて拒否されます）
- 端末情報（デバイストークン、端末種別、OS・アプリのバージョン）
- アラーム要求の履歴（送信元、日時、タイトル、配送結果）

## 削除後に保持されるデータと保持期間

- アプリ内購入の購入履歴は、決済処理と返金対応のため RevenueCat, Inc. および Apple Inc. が各社のポリシーに基づき保持します。RevenueCat には本サービスのアカウント識別子を購入者の識別子として登録しているため、購入履歴は削除したアカウントの識別子に紐づいたまま RevenueCat, Inc. に残ります。提供者のサーバーに保存している有料プランの状態は、アカウントと一緒に削除します<!-- source: Alarmify/Features/Purchase/ProEntitlement.swift: Purchases.logIn に Firebase Auth の uid を渡し RevenueCat の App User ID にしている。firebase/functions/src/account/deleteAccount.ts: deleteUserAccount は users/{uid} (plan を含む) を recursiveDelete で消し、RevenueCat 側の顧客は削除しない -->
- お問い合わせのメールは、対応の記録として受信から 1 年間保持した後に削除します
- サーバーのバックアップに含まれる削除済みデータは、削除から最大 30 日でバックアップの世代交代により消去されます
- 削除処理の完了を確認するための記録 (アカウント識別子のみ。他のデータは含みません) は、通常は削除から 3 時間以内に自動的に消去されます (消去処理が失敗した場合は 1 時間ごとに再試行し、成功した時点で消去されます)

端末内に登録済みの AlarmKit のアラームはアカウント削除では解除されません。iPhone の「時計」アプリまたは Signalarm のアラーム一覧から個別に取り消してください。アプリをアンインストールしても、アカウントとサーバー上のデータは削除されません。
