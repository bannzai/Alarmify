---
paths:
  - "Alarmify/**/*.swift"
  - "AlarmifyWidget/**/*.swift"
  - "Alarmify/Localizable.xcstrings"
---

# ローカライゼーションガイドライン

取り込み元: bannzai/mementomorning の同名ルール。

## 基本ルール

- アプリの基本言語は**英語**。`Text()` などの SwiftUI 標準のローカライズ対象や `String(localized:)` の文字列は、英語圏の文化やテンションになぞった**英文**で書く (英語圏ユーザーにはそのまま表示される)
- コード上のコメントは**日本語** (メインの開発者が日本人だから)
- 翻訳の管理は `Alarmify/Localizable.xcstrings` (String Catalog) で行う。コーディング段階での編集は、コードで追加した英語文言の **ja エントリー追加に限る**。他言語のエントリー追加・既存訳の変更は指示がある時だけ行う (他言語は後で `/translate-app-xcstrings` skill が英語原文と日本語訳を元に一括翻訳する。プロジェクト固有の翻訳スクリプトは新設しない)
- 権限の説明文 (Info.plist の `NS*UsageDescription`) は `Alarmify/InfoPlist.xcstrings` で管理し、en と ja の両方に値を持たせる (en が無いと OS のダイアログにキー名が表示される)

## `// ja:` コメント

- 「アプリの UI 翻訳が必要な箇所」(`Text()` や `String(localized:)`) の直上に `// ja:` で日本語訳を書く。enum ケースやプロパティの説明コメントなど翻訳対象でないものには付けない
- 訳文中の改行は `\n` ではなく、コメントの空行として残す

```swift
// ja: 保存
Text("Save")
```

## 固有名詞と機能名の扱い

- アプリ内の固有名詞・機能名が文中に出てくる場合は、直接文字列に含めず `Text()` の補間で埋め込む (固有名詞も多言語対応の対象であり、Localizable.xcstrings で一元管理するため)
- 固有名詞は引用符で囲む。英語はシングルクォート (`''`)、日本語は (`「」`)
- 外部サービスから送られた文言 (アラームのタイトル等) はユーザー入力値として扱い、翻訳対象にしない

## 関連スクリプト

- `scripts/find_missing_ja_translations.py` - 日本語翻訳の欠落検出
- `scripts/add_translation_comments.py` - 翻訳コメント追加
