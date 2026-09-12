# ホーム

アートボード: `HomeDark` / `HomeLight`。現在の `ContentView` を置き換える。技術検証用のセクション (APNs / FCM トークン・登録済みアラームの一覧・配送先の登録) は開発者メニューへ移す。

## 構成

1. ナビ: large title `Signalarm`、右上に設定 (歯車 22、`accentText`)
2. **次に鳴るアラーム** カード (枠 `accentLine`、18 余白)
   - 1 行目: eyebrow `Next alarm` (左) / `Rings in 9h 12m` (右、13 `fg3`。`Text(fireDate, style: .relative)`)
   - 2 行目: 時刻 `07:30` (等幅 56/60 medium、tabular) + 日付 `Tomorrow` (17 `fg2`。`.dateTime` の相対表記。今日 / 明日以外は `Sep 14`)
   - 3 行目: タイトル 20 semibold (外部サービスの文字列をそのまま。無ければ `Untitled alarm` を `fg3`)
   - 4 行目: トークンの prefix チップ (`accentSoft` の地、等幅 11) + サービス名 (13 `fg3`。トークンのラベル。`../README.md`「前提と未確定事項」)
   - 空状態: 同じカードに `No upcoming alarm` (17 `fg3`) と `Ring a test alarm in 1 minute` の副ボタンを置く。カードの枠は `hair`
3. **Recent alarms** セクション。見出しの右に `Ring a test` (15 `accentText`。テストアラームの登録)
   - 行 (12×16): タイトル 17 semibold (1 行、末尾省略) / 2 行目に日時 (13 `fg3`) + prefix (等幅 11) / 右端に状態 (13 medium `fg3`)
   - 状態の文言は `ContentView.historyStatusText` の既存の分岐をそのまま使う (Rang / Scheduled on this iPhone / Canceled / Waiting for this iPhone / Failed on this iPhone …)。失敗系は `destructive` ではなく `fg3` のまま文言で伝える
   - 末尾の行: 無料プランなら `Older alarms are kept in Pro` (15 `fg3`) + シェブロン → ペイウォール (`.alarmHistory`)。Pro なら表示しない
   - 空状態: `No alarms yet`。読み込み中は `ProgressView`、サインイン中は `Signing in`
4. **Connect** セクション: `API tokens` (鍵のアイコン、右に件数) と `Integration recipes` (プラグのアイコン) の 2 行。既存の `NavigationLink` 先はそのまま

## 確定コピー

| 要素 | en | ja |
| --- | --- | --- |
| eyebrow | Next alarm | 次に鳴るアラーム |
| 残り時間 | Rings in 9h 12m | 9 時間 12 分後に鳴ります |
| 日付 | Tomorrow | 明日 |
| 空状態 | No upcoming alarm | 次に鳴るアラームはありません |
| セクション | Recent alarms / Connect | 直近のアラーム / 連携 |
| セクションの操作 | Ring a test | テストを鳴らす |
| Pro 行 | Older alarms are kept in Pro | それより前の履歴は Pro で見られます |
| Connect 行 | API tokens / Integration recipes | API トークン / 連携レシピ |
