# ペイウォール

アートボード: `PaywallDark` / `PaywallLight`。現在の `PaywallPage` を置き換える。見直しの根拠と確定コピー (en / ja) は `../paywall-review.md`。sheet で表示する。

## 構成

1. 上 59px + 44px の行。右に閉じる (30×30 の丸、`hair` の地、× 16)
2. 見出しブロック (左右 24): eyebrow `Signalarm Pro` → 見出し 30/36 bold → リード 15/21 `fg2` (1 文目は `PaywallTrigger` で変える。2 文目 `Pro removes both limits.` は共通)
3. 特典 4 行 (左右 24、間隔 14): 橙のアイコン 20 + 17 の文言 (鍵 / 無限 / 履歴 / 端末)
4. 伸縮する余白
5. プランカード 2 枚 (左右 16、間隔 8、14×16 余白、角丸 14)
   - 左: ラジオ (22 の丸。選択中は `accent` の塗り + チェック、未選択は `hair2` の枠)
   - 中: プラン名 17 semibold + (年額だけ) `Best value` チップ (`accentSoft`) / 注記 13 `fg3`
   - 右: 価格 17 semibold tabular / 期間 13 `fg3`
   - 選択中の枠は `accent` 1.5px、未選択は `hair2` 1.5px。既定は年額を選択
   - 価格・期間・月額換算は offering の package からだけ組み立てる。取得できない間はカード 2 枚の位置に `Prices couldn't be loaded` と `Reload prices` を出し、CTA を無効にする。annual だけ・monthly だけの時は取れた方の 1 枚だけを出す
6. 主ボタン `Continue with Yearly` (選択に応じて `Continue with Monthly`)。処理中は `ProgressView` を重ねて無効化
7. 注記 11/15 `fg4` 中央 → リンク行 (13 `fg3`、間隔 18): `Restore` / `Terms` / `Privacy` / `Legal notice`
8. 購入・復元の結果 (成功で dismiss、失敗は alert) は既存の `PaywallPage` のロジックをそのまま使う
