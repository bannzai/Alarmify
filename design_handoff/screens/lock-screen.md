# ロック画面 / Dynamic Island (Live Activity)

アートボード: `LockScreen` (ダークのみ。Live Activity は常に暗い地に描かれる)。現在の `AlarmifyWidget/AlarmLiveActivityWidget.swift` の構成を保ち、配色と字詰めだけを揃える。鳴動時の停止 UI はシステム標準 (`AlarmPresentation.Alert`) で差し替えられないため、デザイン対象はカウントダウン中の表示と Dynamic Island の 4 状態。

## ロック画面のバナー

- 地は `Color.black.opacity(0.85)` (`activityBackgroundTint` の既存値)、角丸 22、16 余白
- 左: ベル 26 (`signal`)。中: `SIGNALARM` (11 semibold、tracking 2、`rgba(242,242,240,0.56)`) の下にタイトル 17 semibold (2 行まで)。右: 残り時間 (22 medium、tabular、`signal`。`Text(fireDate, style: .timer)`)
- 既存実装の `.font(.title2.weight(.medium)).monospacedDigit()` と `.caption2.weight(.semibold).tracking(2)` はそのまま

## Dynamic Island

| 状態 | 内容 |
| --- | --- |
| expanded | leading: ベル (`signal`) / center: タイトル 17 semibold / trailing: 残り時間 20 medium tabular (`signal`) |
| compact | leading: ベル 18 / trailing: 残り時間 15 medium tabular (`signal`) |
| minimal | ベル 16 (`signal`) |
| 鳴動中 (alert) | leading: 波付きのベル (`bell.and.waves.left.and.right.fill`) / center: タイトル / trailing: 発火時刻 15 `rgba(242,242,240,0.56)` |

- `keylineTint` は `signal`
- 一時停止 (paused) は trailing に `pause.fill` (既存)。AlarmKit のカウントダウンでは通常到達しないため、アートボードには置いていない

## 実装メモ

- `tintColor` は `AlarmAttributes` から渡る (現在は `Color.signal`)。ダーク / ライトで変えない
- アイコンは SF Symbols のままでよい (アートボードの stroke SVG は見た目の参考)
