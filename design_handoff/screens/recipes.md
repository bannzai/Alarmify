# 連携レシピ

アートボード: `RecipesDark` / `RecipesLight` (一覧)、`RecipeDetailDark` / `RecipeDetailLight` (GitHub Actions の詳細)。現在の `RecipesView` / `RecipeDetailView` を置き換える。内容は `docs/recipes/*.md` と `IntegrationRecipe` が正で、画面は見た目だけを変える。

## 一覧

1. ナビ: `< Signalarm` / `Integration recipes`
2. リード (15/21 `fg2`、左右 20): `Every recipe ends with one request to POST /v1/alarms. Snippets already carry your token.` (`POST /v1/alarms` は等幅 13)。トークン未発行なら 2 文目を `Issue an API token to see these snippets with your token filled in.` (既存文言) にする
3. レシピの行 (13×16): 名前 17 semibold (固有名詞。翻訳しない) / 概要 13/18 `fg3` (既存の `summary`) / シェブロン。順序は `IntegrationRecipe.allCases`
4. **Reference** セクション: `API reference` (本のアイコン) → `https://bannzai.github.io/Alarmify/api`

## 詳細 (GitHub Actions を代表に)

1. ナビ: `< Recipes` / レシピ名 / 右に外部リンクのアイコン (`documentationURL` を Safari で開く)
2. **Steps**: 番号 (等幅 13 `accentText`、幅 16) + 手順 (15/21 `fg2`)。手順中のキー名・フラグは等幅 13。既存の `steps` を使う
3. スニペットごとのセクション (見出しは `snippet.label`): コードブロック (`bg2`、等幅 11/16、`white-space: pre`、横スクロール) + `Copy` の行。YAML は折り返さない (インデントが意味を持つ)
4. 最下段に `gh secret set ALARMIFY_TOKEN` のような 1 行のコマンドも同じコードブロックで出す

## 確定コピー

| 要素 | en | ja |
| --- | --- | --- |
| タイトル | Integration recipes | 連携レシピ |
| リード | Every recipe ends with one request to POST /v1/alarms. Snippets already carry your token. | どのレシピも最後は POST /v1/alarms への 1 リクエストです。スニペットにはトークンが埋め込まれています。 |
| セクション | Reference / Steps / Workflow step / Secret | リファレンス / 手順 / workflow のステップ / シークレット |
| 行 | API reference / Copy | API リファレンス / コピー |
