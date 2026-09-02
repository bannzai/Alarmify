#!/usr/bin/env python3
"""
Localizable.xcstringsで日本語翻訳がないものを検出するスクリプト

このスクリプトは、Localizable.xcstringsファイルを解析し、
日本語("ja")の翻訳が存在しないエントリーを検出して出力します。

使用方法:
    python3 scripts/find_missing_ja_translations.py

オプション:
    --json: JSON形式で出力（Claude等のツールで処理しやすい形式）

出力形式（通常）:
    キー: {key}
    英語: {english_value}
    コメント: {comment}
    ---

出力形式（--json）:
    [
      {
        "key": "...",
        "english": "...",
        "comment": "..."
      },
      ...
    ]
"""

import json
import argparse


# 翻訳スキップ対象のキー（translate_localized_xcstrings.pyと同じ）
SKIP_KEYS = ["", " - ", " / ", "- ", ",", ":"]


def find_missing_ja_translations(localizable_data: dict) -> list[dict]:
    """
    Localizable.xcstringsのデータから日本語翻訳が欠けているエントリーを検出する

    Args:
        localizable_data: Localizable.xcstringsファイルをパースしたdict

    Returns:
        欠けている日本語翻訳のリスト（各要素はkey, english, commentを持つdict）
    """
    missing_ja_translations = []

    # すべてのキーを反復処理
    for key, value in localizable_data.get("strings", {}).items():
        # スキップリスト内のキーは無視
        if key in SKIP_KEYS:
            continue

        # 型チェックを最初に行う（value.getを呼ぶ前に必要）
        if not isinstance(value, dict):
            continue

        # shouldTranslateがfalseに設定されている場合はスキップ
        if value.get("shouldTranslate") is False:
            continue

        # 日本語翻訳を取得
        localizations = value.get("localizations", {})
        ja_localization = localizations.get("ja", {})
        ja_string_unit = ja_localization.get("stringUnit", {})
        ja_value = ja_string_unit.get("value", "")

        # 日本語翻訳が存在しない場合
        if not ja_value:
            # 英語の値を取得（ソース言語）
            en_value = key  # デフォルトはキー自体
            if "en" in localizations:
                en_value = localizations.get("en", {}).get("stringUnit", {}).get("value", key)

            # コメントを取得
            comment = value.get("comment", "")

            missing_ja_translations.append({
                "key": key,
                "english": en_value,
                "comment": comment
            })

    return missing_ja_translations


def main():
    # コマンドライン引数のパース
    parser = argparse.ArgumentParser(
        description="Localizable.xcstringsで日本語翻訳がないものを検出"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="JSON形式で出力（Claude等のツールで処理しやすい形式）"
    )
    args = parser.parse_args()

    # Localizable.xcstringsファイルのパス
    localizable_path = "Alarmify/Localizable.xcstrings"

    # ファイルを読み込み（エラーハンドリング付き）
    try:
        with open(localizable_path, "r", encoding="utf-8") as file:
            localizable_data = json.load(file)
    except FileNotFoundError:
        print(f"エラー: ファイルが見つかりません: {localizable_path}")
        return
    except json.JSONDecodeError as e:
        print(f"エラー: JSONの解析に失敗しました: {e}")
        return

    # 欠けている日本語翻訳を検出
    missing_ja_translations = find_missing_ja_translations(localizable_data)

    # JSON形式で出力
    if args.json:
        print(json.dumps(missing_ja_translations, ensure_ascii=False, indent=2))
        return

    # 通常形式で出力
    print(f"日本語翻訳が欠けているエントリー数: {len(missing_ja_translations)}\n")
    print("=" * 80)

    for item in missing_ja_translations:
        print(f"キー: {item['key']}")
        print(f"英語: {item['english']}")
        if item['comment']:
            print(f"コメント: {item['comment']}")
        print("-" * 80)

    # まとめ情報を出力
    print(f"\n合計: {len(missing_ja_translations)} 件の日本語翻訳が欠けています")


if __name__ == "__main__":
    main()
