# SnapshotUITest Scripts

AlarmifySnapshotUITests を実行して、多言語UIの翻訳検証用スクリーンショットを自動生成するスクリプト群。

## 目的

- 全言語のUIスクリーンショットを自動取得
- 日本語と他言語のスクリーンショットを比較して翻訳の妥当性をチェック
- UI変更後の視覚的回帰テスト

## スクリプト構成

### 環境設定

#### `snapshot_ui_test_env.sh`
環境変数定義と共通関数。

**環境変数:**
- `SCHEME`: AlarmifySnapshotUITests
- `DESTINATION`: iPhone 17 Pro Max
- `DERIVED_DATA_PATH`: artifacts/snapshot_ui_test/derived_data

**共通関数:**
```bash
get_test_info <test_file_path>
# Returns: TEST_PATH ARTIFACT_PATH
```

テストファイルパスから、テスト実行パスとartifactパスを自動生成。

### ビルド・実行

#### `build_snapshot_ui_test.sh`
AlarmifySnapshotUITests を build-for-testing でビルド。

```bash
./scripts/snapshot_ui_tests/build_snapshot_ui_test.sh
```

#### `run_snapshot_ui_test.sh`
個別のテストを test-without-building で実行。

```bash
./scripts/snapshot_ui_tests/run_snapshot_ui_test.sh <TEST_PATH> <RESULT_BUNDLE_PATH>
```

**例:**
```bash
./scripts/snapshot_ui_tests/run_snapshot_ui_test.sh \
  "AlarmifySnapshotUITests/ContentViewSnapshotUITest/testSnapshot" \
  "artifacts/snapshot_ui_test/ContentViewSnapshotUITest/testSnapshot"
```

### メインスクリプト

#### `generate_snapshot_ui_test_screenshots.sh`
全てのSnapshotUITestを実行してスクリーンショットを生成。

**基本使用方法:**
```bash
# 全テスト実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh

# 最初の5個のみ実行（デバッグ用）
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -n 5

# 2番目のテストから3個実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 2 -n 3

# ビルドをスキップして実行（CI並列実行用）
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 5 -n 1 --skip-build

# ヘルプ表示
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh --help
```

**オプション:**
- `-b N`: 開始するテストのインデックス（1から開始、デフォルト: 1）
- `-n N`: 実行するテスト数（デフォルト: 全て）
- `-l LANGS`: 実行する言語をカンマ区切りで指定（例: `"ja,en"`、デフォルト: 全言語）
- `--skip-build`: build-for-testingをスキップ（CI並列実行で既にビルド済みの場合）
- `--overwrite`: 既存スクリーンショットを削除して再撮影（翻訳・画面の変更後に使う。未指定時は対象言語分が揃っているテストをスキップ）
- `-h, --help`: ヘルプメッセージを表示

**処理フロー:**
1. AlarmifySnapshotUITests/Features/**/*SnapshotUITest.swift を検索
2. build-for-testing でビルド（`--skip-build` オプションでスキップ可能）
3. 各テストを -only-testing で個別実行
4. xcrun xcresulttool でスクリーンショットを抽出
5. organize_screenshots.sh でファイル名を整理
6. `scripts/snapshot_ui_tests/screenshots/` に出力

**出力先:**
- `scripts/snapshot_ui_tests/screenshots/` - テストクラス別・言語別に整理されたスクリーンショット

#### `check_translation_quality.sh`
スクリーンショットを使用して翻訳品質をチェックし、問題があればGitHub Issueを自動作成。

**基本使用方法:**
```bash
# 全スクリーンショットをチェック
./scripts/snapshot_ui_tests/check_translation_quality.sh

# 検出 Issue 数の上限を 3 に制限（デバッグ用）
./scripts/snapshot_ui_tests/check_translation_quality.sh -n 3

# Dry run（Issue作成なし、チェックのみ）
./scripts/snapshot_ui_tests/check_translation_quality.sh --dry-run

# ヘルプ表示
./scripts/snapshot_ui_tests/check_translation_quality.sh --help
```

**オプション:**
- `-n N`: 作成する Issue 数の上限（デフォルト: 全て。上限に達した時点でチェックを打ち切る）
- `--dry-run`: 分析は実行し、Issue 作成・画像アップロードだけを省略する
- `-h, --help`: ヘルプメッセージを表示

**処理フロー:**
1. `screenshots/*/` でテストクラスディレクトリを取得
2. 各テストクラス内の `0/`, `1/`, ... をループ
3. `ja.png` を基準に、他言語（`en.png`, `zh-Hans.png` など）を取得
4. Claude CLIで ja.png と各言語の png を比較
5. 翻訳に問題があれば `gh issue create` で自動作成

**チェック基準:**
- 文脈に合わない翻訳
- 用語の不統一
- 文字切れ・表示崩れ
- 未翻訳（日本語のまま）
- 不自然な表現

**作成されるIssue:**
- Title: `翻訳品質改善: {FeaturePage} - {言語} (Index: {インデックス})`
- Labels: `translation`, `i18n`, `quality`
- 問題の詳細、修正方針、チェックリストを含む

**注意事項:**
- Claude CLI実行は時間がかかります（Feature数 × Index数 × 言語数）
- API制限対策のため、各チェック間に2秒の待機時間
- Issue作成の判断はClaude AIが行います

## ワークフロー

### 1. 撮影対象の追加

新しい画面を撮影対象にする時は、次の 2 箇所を追加する。

1. `Alarmify/Features/SnapshotUITest/SnapshotUITestPage.swift` に `SnapshotUITest<{PreviewType}>()` の行を追加
2. `AlarmifySnapshotUITests/Features/{Feature}/{Page}SnapshotUITest.swift` を既存ファイルを雛形に作成

注意: 各 Preview は `PersistenceController.shared.container` (in-memory) を共有するため、
SnapshotUITestPage の wrapper は Preview 本体の評価を表示時まで遅延させて
(`SnapshotUITestLazyPreview`)、撮影対象以外のサンプルデータ挿入が走らないようにしている。
新しい Preview が複数の Preview を持つ場合は wrapper の `previewCount` 引数に個数を渡す。
Preview のシーディング自体も「空の時だけ挿入」で冪等化しておくこと (body の再評価対策)。

### 2. スクリーンショット生成

```bash
# 全テスト実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh
```

### 3. デバッグ実行

```bash
# 最初の3個だけテスト
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -n 3
```

### 4. 翻訳品質チェック

```bash
# スクリーンショット生成後、翻訳品質をチェック
./scripts/snapshot_ui_tests/check_translation_quality.sh

# デバッグ: 最初の3個だけチェック
./scripts/snapshot_ui_tests/check_translation_quality.sh -n 3

# Dry run: Issue作成せずにチェックのみ
./scripts/snapshot_ui_tests/check_translation_quality.sh --dry-run
```

### 5. CI並列実行

```bash
# ジョブ1: 1回だけビルドして1番目のテストを実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 1 -n 1

# ジョブ2: ビルドをスキップして2番目のテストを実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 2 -n 1 --skip-build

# ジョブ3: ビルドをスキップして3番目のテストを実行
./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 3 -n 1 --skip-build
```

## ディレクトリ構造

### スクリプト構成
```
scripts/snapshot_ui_tests/
├── README.md                                    # このファイル
├── snapshot_ui_test_env.sh                      # 環境変数・共通関数
├── build_snapshot_ui_test.sh                    # ビルド
├── run_snapshot_ui_test.sh                      # テスト実行
├── organize_screenshots.sh                      # スクリーンショット整理
├── generate_snapshot_ui_test_screenshots.sh     # メインスクリプト
├── check_translation_quality.sh                 # 翻訳品質チェック&Issue自動作成
├── upload_to_r2.sh                              # Issue へのスクリーンショット添付 (Cloudflare R2)
└── screenshots/                                 # 出力先（自動生成）
```

### スクリーンショット出力構造

実行後、以下のような構造でスクリーンショットが整理されます：

```
scripts/snapshot_ui_tests/screenshots/
├── ContentViewSnapshotUITest/
│   └── 0/                      # Previewインデックス0
│       ├── ja.png              # 日本語
│       └── en.png              # 英語
└── ...

ディレクトリ構造: {テストクラス名}/{インデックス}/{言語コード}.png
- テストクラス名: ContentViewSnapshotUITest など
- インデックス: Previewの番号（0から開始）
- 言語コード: ja, en など
```

### 言語コード一覧

対象言語は `AlarmifySnapshotUITests/Languages.swift` が SSOT。現状は `ja` (日本語) と `en` (英語) の 2 言語で、対応言語を増やす時は同ファイルに追加する。

## 前提条件

- Xcode がインストールされていること
- xcresulttool を使用（Xcodeに同梱されているため追加インストール不要）
- jq コマンドがインストールされていること（スクリーンショット整理に使用）
  ```bash
  brew install jq
  ```
- シミュレータが使用可能であること

## 注意事項

- 実行には時間がかかります（テスト数 × 言語数 × 実行時間）
- シミュレータが自動的に起動します
- テストが失敗しても処理は継続します（set +e）
- 前回の結果は自動的にクリーンアップされます

## トラブルシューティング

### ビルドエラー
```bash
# DerivedDataをクリーンアップ
rm -rf artifacts/snapshot_ui_test
```

### xcresulttool が見つからない
xcresulttoolはXcodeに同梱されています。Xcodeがインストールされていることを確認してください。
```bash
xcrun xcresulttool --version
```

### jq が見つからない
jqコマンドをインストールしてください。
```bash
brew install jq
```

### テストが失敗する
- シミュレータの状態を確認（`xcrun simctl list devices`）
- 撮影対象の Preview 名と SnapshotUITest の `previewType` が一致しているか確認

## 関連スクリプト・ドキュメント

- `upload_to_r2.sh`: Issue へのスクリーンショット添付に使う Cloudflare R2 アップロード（必要な環境変数はファイル内コメント参照）
- `../generate_screenshots/`: App Store 用スクリーンショット生成（別用途）
- `.claude/skills/detect-mistranslation/SKILL.md`: このスクリプト群を使う翻訳品質チェックの skill
