# オンボーディング (5 画面)

アートボード: `Main` (ダークの 1 枚目) / `OnboardingAlarmsDark` / `OnboardingPushDark` / `OnboardingTokenDark` / `OnboardingTestDark` と、対応する `*Light`。設計の根拠と確定コピー (en / ja) は `../onboarding-rationale.md`。

## 共通レイアウト

- 上 59px の安全領域 → 44px の行に 5 分割のプログレスバー (`accent` / `hair2`、高さ 3、間隔 6、左右 20)
- 見出しブロック (左右 24、上 28): eyebrow (等幅 11、`accentText`) → 見出し 34/40 bold → リード 17/24 `fg2`
- 中央のビジュアルは残り高さの中で上下中央 (左右 24)
- 下部: 主ボタン (52 高、`accent`) → テキストボタン (44 高、`fg3`) → 34px のホームインジケータ領域
- 初回起動時だけ表示する。完了・スキップの記録は `@AppStorage` (キー名は変数名と一致させる。`.claude/rules/coding-rules-entity.md`)

## 1. コンセプト (Main / OnboardingConceptLight)

- ビジュアル: 3 段のフローノード (`panel` の地、角丸 14、アイコン 24 + タイトル 17 semibold + 補足 13 `fg3`) を 28px の縦線 (`accentLine`) でつなぐ。3 段目だけ枠を `accentLine`、アイコンを橙にする
- 主ボタン `Get started`。副ボタン無し

## 2. アラームの権限 (OnboardingAlarms*)

- ビジュアル: 権限カード (角丸 16、20 余白)。40×40 の座布団 (`accentSoft`、角丸 10) にベルのアイコン + 見出し 17 semibold、下にチェック (橙 16) 付きの 3 行 (15/21 `fg2`)
- 主ボタン `Allow alarms` で `AlarmKitScheduler.requestAuthorization()` を呼び、結果にかかわらず次へ進む。`Not now` は要求せずに次へ
- 拒否時の再要求は設定 > Permissions から (OS の設定アプリを開く)

## 3. 通知の権限 (OnboardingPush*)

- 構成は画面 2 と同じ。アイコンは iPhone
- 主ボタン `Allow notifications` で `UNUserNotificationCenter.requestAuthorization` → `registerForRemoteNotifications`。`Not now` は要求せずに次へ

## 4. 最初の API トークン (OnboardingToken*)

- 画面表示時に `APITokenModel.issue()` でトークンを発行する (無料枠 1 つ。既にトークンがある再オンボーディングでは発行せず、この画面をスキップする)
- トークンカード (枠 `accentLine`): eyebrow `Token` (`fg3`) → 平文 (等幅 15/22、`word-break: break-all`) → 左に `Shown only once` (13 `fg3`)、右に `Copy` の小ボタン (34 高、`accentSoft` の地、`accentText`)
- curl ブロック (`bg2`、等幅 12/18、折り返し) + `Copy` の行。内容は `APITokenUsageExample.curl` (fire_in 60 秒に読み替えてよい)
- 主ボタン `Continue`。テキストボタン `Issue a token later` は発行せずに次へ (発行済みなら表示しない)
- 発行失敗時はカードの位置にエラー文と再試行ボタンを出す

## 5. テストアラーム (OnboardingTest*)

- カード (`panel`、角丸 16、中央揃え): eyebrow `Test alarm` → `01:00` (等幅 56/60 medium、`accentText`) → `rings after you lock the iPhone` (15 `fg3`)
- 主ボタン `Ring a test alarm in 1 minute` (ベルのアイコン付き) で `ContentView.scheduleTestAlarm` と同じ 1 分後のアラームを登録し、カードの数字をカウントダウンに切り替える。登録後はボタンを `Go to home` に変え、ホームへ進む (鳴るのを待たせない)
- `Skip` は登録せずホームへ
- AlarmKit の権限が無い (画面 2 で Not now) 場合は、ボタンの代わりに `Allow alarms` を出し、許可後にテストアラームへ戻す
