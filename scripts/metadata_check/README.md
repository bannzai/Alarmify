# metadata_check

App Store Connect のメタデータ（name, subtitle, keywords）の文字数制限をチェックするスクリプト群。

## 文字数制限

| ファイル | 上限 |
|----------|------|
| name.txt | 30文字 |
| subtitle.txt | 30文字 |
| keywords.txt | 100文字 |

## スクリプト

### check_length.sh

単一ファイルの文字数をチェックします。

```bash
# 使い方
./check_length.sh <ファイルパス> <上限文字数>

# 例
./check_length.sh fastlane/metadata/ko/name.txt 30
./check_length.sh fastlane/metadata/ko/keywords.txt 100
```

### check_all_metadata.sh

fastlane/metadata配下の全言語のASO関連ファイルを一括チェックします。

```bash
# 全言語をチェック
./check_all_metadata.sh

# 特定言語のみチェック
./check_all_metadata.sh ko
./check_all_metadata.sh ja en-US ko
```

## 終了コード

- `0`: 全てのファイルが制限内
- `1`: 1つ以上のファイルが制限を超えている
- `2`: 引数エラーまたはファイルが存在しない
