# オンボーディング設計の根拠 (/onboarding-design の結果)

`/onboarding-design` (`~/.claude/skills/onboarding-design/SKILL.md`) を Issue #60 の要件で実行した記録。Phase 0 のヒアリングは、無人実行のため AskUserQuestion ではなく Issue #60・#1 と `documents/PROJECT.md` から埋めた。

## Phase 0: アプリ情報 (Issue と PROJECT.md から確定)

| 項目 | 値 | 出典 |
| --- | --- | --- |
| カテゴリ | 開発者向けツール / ユーティリティ (Webhook → AlarmKit のアラーム) | PROJECT.md |
| プラットフォーム | iOS 26+ のみ | PROJECT.md |
| コアバリュー | 外部サービスの HTTP リクエストで iPhone の本物のアラームが鳴る | Issue #1 |
| ターゲット | オンコールのエンジニア、Home Assistant 利用者、サーバー側の予定で起きたい人 | PROJECT.md |
| 現在のオンボーディング | 無し (新規設計) | Issue #60 |
| 設計目標 | リテンション型 (無料枠で「鳴る」体験を完了させる)。課金転換型のペイウォール直行は採らない | Issue #60 のやること 1 |
| 主要市場 | US + JP (英語が基準言語) | Issue #1 の制約 |

### リテンション型を選ぶ根拠

`references/monetization-onboarding.md` の使い分け表に照らすと、Signalarm は「無料で即座にコアバリューを体験できる (ツール)」側に入る。価値は中長期ではなく、最初のテストアラームが鳴った瞬間に現れる。課金転換型 (13〜55 画面の質問・演出・ペイウォール) は Wayk のようなミッション型アラームでは成立しているが、Signalarm の Pro の価値 (複数トークン・無制限・履歴・複数端末) は使い込んでから効くもので、インストール直後に約束しても自分ごとにならない。よって 8BP を軸に最短で「1 回鳴った」まで誘導し、Pro の導線はホームの履歴と設定に静かに置く (paywall-review.md の「有料プランを隠さない」の手当てを参照)。

## Phase 1: 参考 UI の収集

ギャラリーサイトの巡回 (`/onboarding-design collect`) は行っていない。理由: 本 issue の完了条件はカンバスと `design_handoff/` の成果物で、参考画像の収集は完了条件に含まれない。トーンとマナーは Issue #1 が確定しており (開発者向けの「信頼できる計器」、ダーク前提、橙 1 色)、ギャラリーの一般的なオンボーディング UI を当てはめる余地が小さい。収集が必要になったら `/onboarding-design collect` を別途実行する。

## Phase 2: 推奨タイプ

`references/onboarding-types.md` の分類で、第 1 推奨は **クイックウィン型** (2 分以内にテストアラームが鳴る)、第 2 推奨は **パーミッションプライミング型** (AlarmKit と通知の 2 つの権限を、理由を示してから要求する)。生産性カテゴリの推奨 (プログレッシブ + クイックウィン) のうち、プログレッシブは機能数が少ないため画面としては採らず、レシピ・履歴などは使う場面で見せる。

## Phase 3: 画面フロー (5 画面)

| # | アートボード | 目的 | 対応 BP |
| --- | --- | --- | --- |
| 1 | Main / OnboardingConceptLight | コンセプト提示。Your service → Signalarm API → This iPhone rings の 3 段で「Webhook → 本物のアラーム」を 1 画面で理解させる | #1 価値を見せる |
| 2 | OnboardingAlarms* | AlarmKit の権限。「何ができる権限か」を 3 点で示してから要求する | #5 権限タイミング |
| 3 | OnboardingPush* | 通知の権限。push が「サービスからの到達経路」であることを示す。マーケティング通知ではないと明言する | #5 権限タイミング |
| 4 | OnboardingToken* | 最初の API トークン発行。平文 + コピー + そのまま実行できる curl。「Issue a token later」でスキップ可 | #4 クイックウィン、#7 次のステップ |
| 5 | OnboardingTest* | 1 分後のテストアラーム。「Lock the iPhone and wait」で最初の成功体験を 1 回実行させて終わる | #4 クイックウィン、#7 次のステップ |

- 進捗は画面上部の 5 分割バーで示す (#6)。eyebrow は「Step n of 4」で、コンセプト画面は数えない
- 権限の順序は AlarmKit → 通知。アラームが鳴れないと通知を許可する意味が無いため、より本質的な権限を先に置く
- 完了の定義は「テストアラームが 1 回鳴った」。説明で終わらせない (SKILL.md の完了基準)

## 8 つのベストプラクティス照合

| BP# | 項目 | 対応 | 実装メモ |
| --- | --- | --- | --- |
| 1 | 価値を見せる | ○ | 画面 1 でコンセプトを図で示し、サインアップは無い (匿名認証で自動) |
| 2 | プログレッシブ | ○ | 機能ツアーをしない。レシピ・履歴・Pro はホーム以降で文脈に応じて見せる |
| 3 | パーソナライズ | △ | 質問画面を置かない (回答の使い道が無い)。トークンが「自分のもの」になる画面 4 が代替 |
| 4 | クイックウィン | ○ | 画面 5 で 1 分後に鳴る |
| 5 | 権限タイミング | ○ | 権限ごとに理由を 1 画面ずつ。Not now でスキップでき、設定の Permissions から後で許可できる |
| 6 | プログレス表示 | ○ | 5 分割バー + Step n of 4 |
| 7 | 次のステップ | ○ | 最後がテストアラームで、鳴った後はホームに「Next alarm」と履歴が出る |
| 8 | 透明性 | ○ | 画面 4 と 5 は通常利用と同じ操作 (トークン発行・テストアラーム) をしている |

## プラットフォーム差異

- iOS のみ。権限ダイアログはシステム標準で、画面 2・3 はその前置き (pre-permission)
- AlarmKit の権限を拒否した場合、画面 2 に戻さず先へ進め、設定の Permissions に「Denied」と OS の設定を開く導線を出す

## 計測

PROJECT.md の方針で Analytics は MVP に入れないため、計測イベント (`references/monetization-onboarding.md` の最低 8 イベント) は本設計に含めない。導入する時は「オンボーディング開始 / 各ステップ表示 / 完了 / テストアラーム発火 / ペイウォール表示 / 閉じる / 購入完了」を最低セットにする (paywall-review.md も参照)。

## 確定コピー

短い文言は `~/.claude/rules/coding-rules-user-facing-short-copy-punctuation.md` に照合済み (見出し・ボタンに句読点を置かない。リード文は複数文のため通常の句読点)。

| 画面 | 要素 | en | ja |
| --- | --- | --- | --- |
| 1 | eyebrow | Signalarm | Signalarm |
| 1 | 見出し | Turn any webhook into a real alarm | どんな Webhook も本物のアラームに |
| 1 | リード | Send one HTTP request from your service and this iPhone rings. Not a notification but an alarm that cuts through Silent mode and Focus even when the app is closed. | サービスから HTTP リクエストを 1 つ送るだけで、この iPhone が鳴ります。通知ではなくアラームなので、サイレントモードや集中モードでも、アプリを閉じていても鳴ります。 |
| 1 | 図 | Your service / Signalarm API / This iPhone rings | あなたのサービス / Signalarm API / この iPhone が鳴る |
| 1 | 主ボタン | Get started | はじめる |
| 2 | eyebrow | Step 1 of 4 | ステップ 1 / 4 |
| 2 | 見出し | Allow alarms | アラームを許可 |
| 2 | リード | Signalarm rings through AlarmKit, the same system as the built-in Clock. Nothing can ring without this permission. | Signalarm は標準の時計と同じ AlarmKit で鳴ります。この許可が無いと何も鳴りません。 |
| 2 | カード | What alarms can do / Ring in Silent mode and every Focus / Show full screen on the Lock Screen / Keep ringing until you stop them | アラームにできること / サイレントモードと集中モードでも鳴る / ロック画面に全画面で表示 / 止めるまで鳴り続ける |
| 2 | ボタン | Allow alarms / Not now | アラームを許可 / あとで |
| 3 | 見出し | Allow notifications | 通知を許可 |
| 3 | リード | Your services reach this iPhone through push. That is how an alarm request arrives while the app is closed. | サービスからの依頼は push でこの iPhone に届きます。アプリを閉じている間もアラームの依頼を受け取れます。 |
| 3 | カード | What push is used for / Deliver alarm requests from your services / Schedule the alarm in the background / No marketing and no unrelated banners | push の用途 / サービスからのアラーム依頼を届ける / バックグラウンドでアラームを登録する / 宣伝や無関係なバナーは送らない |
| 3 | ボタン | Allow notifications / Not now | 通知を許可 / あとで |
| 4 | 見出し | Your first API token | 最初の API トークン |
| 4 | リード | Paste it into the service that should wake you. It is shown only once. | 鳴らしたいサービスに貼り付けてください。表示されるのは今だけです。 |
| 4 | カード | Token / Shown only once / Copy | トークン / 表示は今だけ / コピー |
| 4 | ボタン | Continue / Issue a token later | 次へ / あとで発行する |
| 5 | 見出し | Hear it ring | 鳴らしてみる |
| 5 | リード | Schedule a test alarm one minute from now. Lock the iPhone and wait. Real requests from your services work the same way. | 1 分後にテストアラームを登録します。iPhone をロックして待ってください。サービスからの本番の依頼も同じように鳴ります。 |
| 5 | カード | Test alarm / 01:00 / rings after you lock the iPhone | テストアラーム / 01:00 / iPhone をロックすると鳴ります |
| 5 | ボタン | Ring a test alarm in 1 minute / Skip | 1 分後にテストアラームを鳴らす / スキップ |
