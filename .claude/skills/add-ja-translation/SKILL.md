---
name: add-ja-translation
description: Text/String(localized:)に// ja:コメントを追記し、Localizable.xcstringsに日本語翻訳を追加
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Add Japanese Translation

SwiftUI コード内の翻訳対象文字列に `// ja:` コメントを追加し、`Localizable.xcstrings` に日本語翻訳エントリーを追加する。新しい UI テキストを追加した時、`// ja:` コメントの不足や翻訳漏れを修正する時に使う。

書き方のルール（`// ja:` の付け方・固有名詞の埋め込み・ja のみ追加）は `.claude/rules/localization-guidelines.md` が SSOT（対象ファイル操作時に自動ロード）。エンティティに入れる文字列の扱いは `.claude/rules/coding-rules-entity.md` に従う。

## 手順

1. `python scripts/find_missing_ja_translations.py` で翻訳漏れを検出する
2. 検出箇所の `Text()` / `String(localized:)` の直上に `// ja:` コメントを追加する（`scripts/add_translation_comments.py` で機械的に追加できる）
3. `Localizable.xcstrings` に該当の英語文言のエントリーを追加し、ja の localization のみを入れる（既存エントリーの形式に合わせる）

## 完了基準

- [ ] `find_missing_ja_translations.py` の検出が 0 件
- [ ] 固有名詞が `Text()` の補間で埋め込まれている
- [ ] 英文が英語圏の文化やテンションになぞって作成されている
