# API トークン

アートボード: `TokensDark` / `TokensLight`。現在の `APITokenView` を置き換える。

## 構成

1. ナビ: `< Signalarm` / タイトル `API tokens`
2. **新しいトークン** カード (発行直後だけ。枠 `accentLine`、16 余白)
   - eyebrow `New token` (左) / `Shown only once` (右、13 `fg3`)
   - 平文 (等幅 15/22、`word-break: break-all`、`textSelection`)
   - ボタン行: `Copy token` (40 高、`accent` の塗り、コピーのアイコン) が伸びる / `Done` (副、40 高)。`Done` で `APITokenModel.dismissIssued()`
3. **Tokens** セクション: トークンごとに 1 カード
   - 1 行目: prefix (等幅 17) + `Created Sep 12 · 3 alarms this month` (13 `fg3`。今月の件数は `AlarmHistoryEntry.tokenID` で数える。無料枠の残量を意識させる) / 右に `Revoke` (15 `fg3`。確認ダイアログの後 `revoke`)
   - curl ブロック (`bg2`、等幅 12/18、折り返し) + `Copy`。平文は発行直後しか無いため、それ以外は `alm_9f2c…` のように prefix + 省略記号で埋める (コピー時も同じ。ユーザーが自分で置き換える)
   - `Recipes` + チップ (`GitHub Actions` / `Home Assistant` / `Shortcuts`)。タップで `RecipeDetailView` (このトークンの平文があれば埋め込む)
   - 空状態: `No tokens yet` (17 `fg3`) の 1 行カード
4. `Issue a token` 副ボタン (48 高) + 補足 `The free plan includes one token and 20 alarms a month` (13 `fg3`、中央)。上限で拒否されたらペイウォール (`.freeQuotaExceeded`)。Pro では補足を出さない
5. エラーはカードの下に `destructive` の文で出す (既存の `errorMessage`)

## 確定コピー

| 要素 | en | ja |
| --- | --- | --- |
| タイトル | API tokens | API トークン |
| 新規カード | New token / Shown only once / Copy token / Done | 新しいトークン / 表示は今だけ / トークンをコピー / 完了 |
| セクション | Tokens | トークン |
| 行 | Created Sep 12 · 3 alarms this month / Revoke | 9 月 12 日に発行 · 今月 3 回 / 失効 |
| レシピ | Recipes | レシピ |
| ボタン | Issue a token | トークンを発行 |
| 補足 | The free plan includes one token and 20 alarms a month | 無料プランはトークン 1 つと月 20 回のアラームまで |
| 空状態 | No tokens yet | トークンはまだありません |
