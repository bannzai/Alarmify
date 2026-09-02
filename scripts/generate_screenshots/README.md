# App Store Screenshot Scripts

AppStoreScreenshotsUITests を実行して、App Store 用スクリーンショットを多言語で自動生成するスクリプト群。
(取り込み元: bannzai/mementomorning の同名ディレクトリ。手法は `/appstore-screenshot-builder` skill の SnapshotUITest 方式)

## 仕組み

1. `AppStoreScreenshots/Sources/` のスクショページ (背景 + キャッチコピー + デバイスフレーム + モック画面) を SwiftUI で実装
2. `AppStoreScreenshotsUITests` が各ページを言語ごとに起動してキャプチャ (`XCTAttachment`)
3. `xcresulttool` で画像を抽出し、fastlane 形式 (`{index}_{表示サイズ名}_{index}.png`) に整理
4. バリアント別に `artifacts/_variant-{name}/{言語}/` へ出力し、`apply_variant.sh` で `fastlane/screenshots/` に適用

## スクリプト構成

```
scripts/generate_screenshots/
├── README.md                          # このファイル
├── appstore_screenshot_env.sh         # 環境変数・共通関数 (バリアント定義・撮影デバイス定義・言語マッピング・シミュレータ自動作成)
├── build_appstore_screenshot.sh       # build-for-testing
├── run_appstore_screenshot.sh         # 個別テストを test-without-building で実行
├── organize_appstore_screenshots.sh   # 抽出画像を fastlane 形式に整理
├── generate_appstore_screenshots.sh   # メインスクリプト (ビルド → 実行 → 抽出 → 整理)
└── apply_variant.sh                   # 選択バリアントを fastlane/screenshots/ に適用
```

## 使い方

```bash
# 全言語 (ja, en)・全番号・全デバイス (6.9 インチ + 6.5 インチ) で生成
./scripts/generate_screenshots/generate_appstore_screenshots.sh

# 1枚だけ日本語・6.9 インチで生成 (動作確認用)
./scripts/generate_screenshots/generate_appstore_screenshots.sh -l "ja" -n "1" -d "69"

# 並列数・ビルドスキップ・上書き
./scripts/generate_screenshots/generate_appstore_screenshots.sh -p 1 --skip-build --overwrite

# 生成したバリアントを fastlane/screenshots/ に適用
./scripts/generate_screenshots/apply_variant.sh signal
```

## バリアントと番号

スクリーンショット番号とバリアントの対応は `appstore_screenshot_env.sh` の `get_variant_name` が SSOT。
現状は 1〜5 が `signal` (夜色の地 + 橙のシグナルの微光 + 極太左揃え見出し) の 1 バリアントのみ。
5 枚の訴求軸は次の通り。

| 番号 | 訴求軸 |
| --- | --- |
| 1 | Webhook が本物のアラームになる |
| 2 | サイレントモード・集中モードを突破して鳴る |
| 3 | CI・監視・ホームオートメーションなど何とでもつながる |
| 4 | POST ひとつでアラームを登録できる |
| 5 | サーバーから取り消し・時刻変更ができる |

訴求軸のバリアントを追加する時は 5 枚単位で番号帯を割り当て (6〜10 が次のバリアント、...)、対応する
`AppStoreScreenshots/Sources/Layouts/` のレイアウト・ページと
`AppStoreScreenshotsUITests/Features/AppStoreScreenshot/` のテストを追加する。

## 撮影デバイス (表示サイズ)

デバイスと出力ファイル名の対応は `appstore_screenshot_env.sh` の `get_display_type` / `get_device_type_name` が SSOT。
`-d` (または `SCREENSHOT_DEVICES`) で指定し、既定は両方 (`69,65`)。

| 区分 | シミュレータ | 解像度 | ファイル名 | App Store Connect での扱い |
| --- | --- | --- | --- | --- |
| `69` | iPhone 17 Pro Max | 1320×2868 | `{index}_APP_IPHONE_67_{index}.png` | 6.9 インチ (必須) |
| `65` | iPhone 13 Pro Max | 1284×2778 | `{index}_APP_IPHONE_65_{index}.png` | 6.5 インチ (任意。未提供なら 6.9 インチの縮小が使われる) |

ファイル名の表示サイズ名は fastlane deliver の DisplayType に合わせる (deliver は 6.9 インチを `APP_IPHONE_67` として扱う。
アップロード時の区分判定は画像の解像度で行われる)。
参照: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

## 対象言語

`AppStoreScreenshotsUITests/Languages.swift` が SSOT。現状は ja / en の 2 言語。
fastlane ディレクトリ名への変換 (en → en-US) は `appstore_screenshot_env.sh` の `map_language_to_fastlane` で行う。

## 前提条件

- Xcode (xcresulttool 同梱)
- jq (`brew install jq`)
- iOS 26.0 ランタイムのシミュレータ (無ければ `iPhone 17 Pro Max` / `iPhone 13 Pro Max` を自動作成する)

## 注意事項

- UITest はローカルシミュレータでしか実行できないため、リモート simulator (simtunnel) では生成できない
  (CLAUDE.md「検証方法」のローカル sim フォールバックに該当)
- 複数 worktree で同時に生成する時は `DESTINATION_SIM_NAME` で専用シミュレータ名を渡して分離する (専用名は 1 機種分にしか付けられないため、`-d` で 1 デバイスに絞って実行する)
- 生成した画像は `apply_variant.sh` で `fastlane/screenshots/{locale}/` に配置し、git にコミットする (中間出力の `artifacts/` は .gitignore 済みで、`fastlane/screenshots/` だけがコミット対象)
