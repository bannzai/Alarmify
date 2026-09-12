# デザイントークン

ダークの値は既存の `Alarmify/Shared/DesignTokens.swift` (`night` / `panel` / `paper` / `signal` / `hairline`) と `docs/index.html` の CSS 変数 (`--bg-2` / `--fg-2` / `--fg-3` / `--hair-2` / `--accent-soft` / `--accent-line`) から転記した。ライトはリポジトリに定義が無かったため本 issue で新設した (Issue #1「ダークモードを優先しつつライトモードでも破綻しない配色」)。`canvas/build.mjs` の `themes` は本表と同じ値。

## 色

| トークン | 用途 | ダーク | ライト |
| --- | --- | --- | --- |
| `bg` | 画面の地 | `#0A0A0B` | `#F5F5F3` |
| `bg2` | コードブロック・インセットの地 | `#0F1012` | `#ECECE9` |
| `panel` | カード・行の地 | `#15161A` | `#FFFFFF` |
| `fg` | 一次テキスト | `#F2F2F0` | `#111113` |
| `fg2` | 二次テキスト (リード文・本文) | `rgba(242,242,240,0.76)` | `rgba(17,17,19,0.72)` |
| `fg3` | 三次テキスト (補足・セクション見出し・状態) | `rgba(242,242,240,0.56)` | `rgba(17,17,19,0.52)` |
| `fg4` | 微弱 (法務の注記・シェブロン・ホームインジケータ) | `rgba(242,242,240,0.35)` | `rgba(17,17,19,0.36)` |
| `hair` | 区切り線・カードの枠 | `rgba(242,242,240,0.10)` | `rgba(17,17,19,0.10)` |
| `hair2` | 二次ボタンの枠・未選択のプランの枠 | `rgba(242,242,240,0.16)` | `rgba(17,17,19,0.16)` |
| `accent` | 主ボタンの塗り・大きな数字・アイコン・プログレス | `#F97316` | `#F97316` |
| `accentText` | 小さな橙のテキスト (eyebrow・リンク・ナビの戻る) | `#F97316` | `#C2410C` |
| `accentSoft` | 橙のチップ・アイコンの座布団 | `rgba(249,115,22,0.14)` | `rgba(249,115,22,0.12)` |
| `accentLine` | 強調カードの枠 (次のアラーム・新しいトークン・選択中のプラン) | `rgba(249,115,22,0.40)` | `rgba(249,115,22,0.45)` |
| `onAccent` | 橙の上のテキスト | `#0A0A0B` | `#FFFFFF` |
| `destructive` | アカウント削除 | `#FF453A` (iOS systemRed dark) | `#FF3B30` (iOS systemRed light) |

- アクセントは橙 1 色。鳴ること・鳴らす操作・注意を引く枠だけに使い、装飾には使わない
- ライトで小さな橙テキストを `#C2410C` に落とすのは、`#F97316` の白地に対するコントラスト比が約 2.9:1 で 13px 前後の文字では読みにくいため (`#C2410C` は約 5.2:1)。塗り・56px の数字・20px 以上のアイコンは `#F97316` のまま
- SwiftUI へ落とす時は `Color.signal` 等の既存名を保ち、ライト版は Asset Catalog の Any / Dark appearance で分ける

## タイポグラフィ

書体はシステム (SF Pro Text / SF Mono)。等幅はトークン・curl・コード・時刻の数字・eyebrow にだけ使う。

| 役割 | サイズ / 行高 / ウェイト | SwiftUI |
| --- | --- | --- |
| Large title (ホームのタイトル) | 34 / 41 / bold, letter-spacing −0.02em | `.largeTitle.bold()` |
| オンボーディングの見出し | 34 / 40 / bold, −0.02em | `.largeTitle.bold()` |
| ペイウォールの見出し | 30 / 36 / bold, −0.02em | `.title.bold()` |
| Title 3 (次のアラームのタイトル) | 20 / 25 / semibold | `.title3.weight(.semibold)` |
| Headline (行のタイトル・ナビタイトル) | 17 / 22 / semibold | `.headline` |
| Body (行のラベル・リード文) | 17 / 24 / regular | `.body` |
| Subheadline (説明・手順) | 15 / 21 / regular | `.subheadline` |
| Footnote (補足・状態・注記) | 13 / 18 / regular | `.footnote` |
| Caption 2 (法務の注記) | 11 / 15 / regular | `.caption2` |
| Section header | 13 / semibold, letter-spacing 0.04em, 大文字 | `.footnote.weight(.semibold)` + `.textCase(.uppercase)` |
| Eyebrow (等幅) | 11 / 等幅, letter-spacing 0.2em, 大文字 | `.caption2.monospaced()` |
| 時刻の数字 (等幅) | 56 / 60 / medium, −0.02em, tabular | `.system(size: 56, weight: .medium, design: .monospaced).monospacedDigit()` |
| トークン (等幅) | 15 / 22 | `.subheadline.monospaced()` |
| チップ (等幅) | 11 / letter-spacing 0.02em | `.caption2.monospaced()` |
| コード (等幅) | 12 / 18 (長い YAML は 11 / 16) | `.caption.monospaced()` |

## 余白・角丸・寸法

| 項目 | 値 |
| --- | --- |
| 画面の左右余白 | 16 (カード)、20〜24 (見出し・本文) |
| セクション見出しの上下 | 上 20 / 下 8 (設定のように密な画面は上 14 / 下 6) |
| 行の高さ | 最小 48、内側 13×16 (履歴は 12×16) |
| カードの角丸 | 14 (権限カードと Live Activity は 16 / 22) |
| ボタンの角丸 | 12 (主 52 高・副 48 高・テキスト 44 高)、小ボタン 10 (40 高)、チップ 13 (26 高) |
| コードブロックの角丸 | 10 |
| ヘアライン | 1px `hair` |
| 上部の安全領域 | 59 (status bar は描かない)、ナビバー 44 |
| 下部の安全領域 | 34 (ホームインジケータ) |
| オンボーディングのプログレス | 5 分割、高さ 3、間隔 6 |
| タップ領域 | 最小 44 |

## 状態と強調

- 強調カード (次のアラーム・新しいトークン・選択中のプラン) は枠を `accentLine` にするだけで、地の色は `panel` のまま
- 主ボタンは `accent` の塗り + `onAccent` の文字。1 画面に 1 つ
- 副ボタンは `hair2` の枠 + `fg2` の文字。テキストボタンは `fg3`
- 状態の語 (Rang / Scheduled on this iPhone / Canceled) は `fg3`、取り消しは `fg4`。色で成否を分けない (橙は鳴ることにだけ使う)
