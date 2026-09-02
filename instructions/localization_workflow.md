# ブランチ変更の翻訳追加手順書

## 概要
このドキュメントは、ブランチで追加された新しい文字列を見つけ出し、`Localizable.xcstrings`に日本語翻訳を追加する手順をまとめたものです。

## 手順

### 1. 変更ファイルの特定
```bash
# 変更されたファイルの一覧を取得
git diff origin/main --name-only
```

### 2. 新しい文字列の抽出
```bash
# 変更内容を確認し、Text()やString(localized:)の使用箇所を探す
git diff origin/main -- [ファイルパス]
```

#### 探すべきパターン
- `Text("...")`
- `String(localized: "...")`
- `.accessibilityLabel(String(localized: "..."))`
- その他SwiftUIの翻訳対象文字列

### 3. 既存の翻訳を確認
各文字列がすでに`Localizable.xcstrings`に存在するか確認：

```bash
# 特定の文字列を検索
grep "\"検索する文字列\"" /path/to/Localizable.xcstrings

# 複数の文字列を一度に確認
grep -E "\"(String1|String2|String3)\"" /path/to/Localizable.xcstrings
```

### 4. 翻訳の追加

#### 4.1 JSONファイルの構造
`Localizable.xcstrings`は以下の構造を持つJSONファイルです：

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "String key" : {
      "localizations" : {
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "日本語訳"
          }
        }
      }
    }
  }
}
```

#### 4.2 インデント規則
- 文字列キー: 4スペース
- "localizations": 6スペース
- 言語コード ("ja"): 8スペース
- "stringUnit": 10スペース
- "state"と"value": 12スペース

#### 4.3 挿入位置の特定
文字列はアルファベット順に並んでいるため、正しい位置を見つける：

```bash
# 前後の文字列を確認
grep -B2 -A2 "\"類似の文字列\"" /path/to/Localizable.xcstrings

# 特定の文字で始まる文字列を探す
grep -n "^    \"[A-Z][^\"]*\" : {$" /path/to/Localizable.xcstrings
```

### 5. JSONの検証
変更後、JSONが有効であることを確認：

```bash
python3 -m json.tool /path/to/Localizable.xcstrings > /dev/null && echo "JSON is valid"
```

## 注意事項

### 1. 重複の確認
- 大文字・小文字の違いに注意（例: "Close" vs "close"）
- 既存の類似文字列がないか確認

### 2. 翻訳ルール
- 日本語（ja）の翻訳のみを追加
- 他の言語は後で翻訳APIで一括処理されるため追加しない
- `"state" : "translated"`を必ず含める

### 3. コメントの活用
コード内のコメントから翻訳を取得：
```swift
// ja: 友達を招待
.accessibilityLabel(String(localized: "Invite friends"))
```

### 4. エラー対処
- JSONフォーマットエラーが発生した場合は、インデントとカンマを確認
- 最後のエントリーにはカンマを付けない
- 文字列内のダブルクォートはエスケープする

## スクリプト例

### 新しい文字列の一括検索
```bash
#!/bin/bash
# find_new_strings.sh

# 変更されたSwiftファイルから翻訳対象文字列を抽出
git diff origin/main --name-only | grep "\.swift$" | while read file; do
    echo "=== $file ==="
    git diff origin/main -- "$file" | grep -E '\+.*String\(localized:|Text\("' | grep -v "^+++"
done
```

### 文字列の存在確認
```bash
#!/bin/bash
# check_strings.sh

XCSTRINGS_FILE="/path/to/Localizable.xcstrings"

# チェックしたい文字列のリスト
strings=(
    "Invite friends"
    "Shield preview"
    "Pomodoro settings"
)

for str in "${strings[@]}"; do
    if grep -q "\"$str\"" "$XCSTRINGS_FILE"; then
        echo "✅ Found: $str"
    else
        echo "❌ Missing: $str"
    fi
done
```

## トラブルシューティング

### 大きなdiffが出る場合
- インデントが統一されているか確認
- 改行コードが一致しているか確認
- JSONフォーマッタの設定を確認

### 文字列が見つからない場合
- 大文字・小文字を確認
- 部分一致で検索してみる
- エスケープ文字に注意

## まとめ
1. `git diff`で変更を確認
2. 新しい文字列を抽出
3. 既存の翻訳を確認
4. アルファベット順の正しい位置に挿入
5. JSONを検証

この手順に従うことで、効率的かつ正確に翻訳を追加できます。