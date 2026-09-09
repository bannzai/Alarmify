# App Store 製品ページヘッダー

全言語共通の文字なし入稿素材。`header.jpg` が完成品、`prompt.txt` が生成に使用したプロンプト。

## 訴求と根拠

「外部から届いた信号が本物のアラームになる」を、無地の立方体からベルへ流れる光で表現する。
`fastlane/metadata/{ja,en-US}/` の name・subtitle・description にある Webhook / API からアラームを鳴らす価値を、一つの場面に絞った。
配色は `AppStoreScreenshots/Sources/DesignTokens.swift` の夜色・シグナル橙・紙色・パネル色に基づく。
実在サービスのロゴや画面を使わず、全言語で同じ画像を使用できる。

## 仕様と制作方法

2026-09-09 に Apple 公式 PSD を取得し、canvas 3840×1646、Art Safe Area の座標 (左1097、上493、右2743、下1154) を実測した。
公式の仕様・デザイン指針: https://developer.apple.com/app-store/asset-best-practices/

画像生成は依頼で指定された `gen-header-4k.sh` に `prompt.txt` を渡し、21:9 / 4K で実行した。
生成は非決定的なため、同じプロンプトでも同一画像になるとは限らない。入稿時はコミットされた `header.jpg` を使用する。

リポジトリルートで実行する正規化・検証コマンド:

```sh
bash ~/.agents/skills/appstore-header-creative/scripts/fetch_template_spec.sh --type header --cache-dir ./tmp/appstore-header-creative
cp tmp/header-generated.png tmp/header-source.jpg
bash ~/.agents/skills/appstore-header-creative/scripts/normalize_asset.sh tmp/header-source.jpg tmp/header-normalized.jpg --type header
sips -s format jpeg -s formatOptions 95 tmp/header-normalized.jpg --out appstore/product-page-header/header.jpg
bash ~/.agents/skills/appstore-header-creative/scripts/check_header_asset.sh appstore/product-page-header/header.jpg --type header
```

## 検証結果

生成・正規化・JPEG書き出し・入稿前検査はいずれも exit 0。生成画像は6336×2688で、拡大せず正規化した。

```text
[OK] フォーマット: jpeg
[OK] サイズ: 3840x1646
[INFO] Art Safe Area (実画像換算): left=1097 top=493 right=2743 bottom=1154 — キーコンテンツ・コピーはこの範囲内に収める
```

入稿前検査は OK 2件、WARN 0件、NG 0件。公開用ファイルの `check-upload-target.sh` も exit 0。
完成したJPEGを開き、文字・数字・実在ロゴ・個人情報・秘匿情報がないことと、立方体・光の線・ベル・発光アークがセーフエリア内に収まることを目視確認した。

生成ライブラリは AFC 呼び出し方法の非推奨警告を出したが、画像の保存まで正常終了した。
生成元は拡張子が `.png` でも実体がJPEGだったため、拡張子を揃えたコピーを正規化した。
正規化時には macOS の `kern.hv_vmm_present` 取得失敗の診断が出たが、寸法・形式の検査に合格した。
アプリコードの変更はないため、アプリのビルド・テストは実行していない。

## 適用範囲

今回の成果物は文字なしヘッダーの入稿ファイル。既存の `fastlane/creative_assets/` の言語別素材、検索結果用画像、LP の OGP と生成スクリプトは変更しない。
App Store Connect の入稿先確認・アップロード・受理結果の確認は依頼により対象外。

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/appstore-header-creative
codex resume 01a08542-9a5c-7251-9a9d-d71048a4e70d
```
