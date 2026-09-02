#!/usr/bin/env python3
"""
Localizable.xcstringsにSwiftコードの使用状況を分析して翻訳補助コメントを追加するスクリプト。

このスクリプトはSwiftコードを分析して翻訳キーがどこで使われているかを理解し、
翻訳者がコンテキストを理解できるように適切な日本語コメントを生成します。

使用方法:
    python scripts/add_translation_comments.py --mode diff      # 不足しているコメントを追加（デフォルト）
    python scripts/add_translation_comments.py --mode overwrite # すべてのコメントを上書き
    python scripts/add_translation_comments.py --mode reanalyze # 不適切なコメントをレビューして修正
    python scripts/add_translation_comments.py -n 10           # 10個の翻訳のみ処理
    python scripts/add_translation_comments.py -v              # 詳細なログを有効化

必要条件:
    - Claude CLIがインストール・設定されていること
    - リポジトリのルートディレクトリから実行すること
    - Localizable.xcstringsファイルがAlarmify/Localizable.xcstringsに存在すること

スクリプトの動作:
1. Localizable.xcstringsのJSONファイルを読み込む
2. 各翻訳キーに対して、指定されたLLM CLIを使用してSwiftコードの使用状況を分析
3. コンテキストと使用方法を説明する日本語コメントを生成
4. 新しいコメントでLocalizable.xcstringsファイルを更新
"""

import json
import os
import subprocess
import argparse
import sys
import re
from typing import Dict, Any, Optional, List

# Localizable.xcstringsファイルのパス
LOCALIZABLE_PATH = "../Alarmify/Localizable.xcstrings"
SWIFT_CODE_PATH = "../Alarmify"

def escape_key_for_regex(key: str) -> str:
    """翻訳キーをSwiftコード検索用の正規表現パターンに変換
    
    例:
    - "Hello %@" -> "Hello \\([^)]+\\)"
    - "%lld minute" -> "\\([^)]+\\) minute"
    - "%@ - %lld items" -> "\\([^)]+\\) - \\([^)]+\\) items"
    """
    # まずフォーマット指定子を一時的なプレースホルダーに置換
    # %@, %lld, %d, %f, %1$@, %2$d などにマッチ
    placeholder = '<<<FORMAT_SPECIFIER>>>'
    temp = re.sub(r'%(?:\d+\$)?[a-zA-Z@]+', placeholder, key)
    
    # %% を一時的なプレースホルダーに置換
    percent_placeholder = '<<<PERCENT>>>'
    temp = temp.replace('%%', percent_placeholder)
    
    # 残りの文字列をエスケープ
    escaped = re.escape(temp)
    
    # プレースホルダーをSwiftの文字列補間パターンに置換
    pattern = escaped.replace(placeholder, r'\\([^)]+\\)')
    
    # パーセントプレースホルダーを % に戻す
    pattern = pattern.replace(percent_placeholder, '%')
    
    return pattern

def find_key_usage(key: str, verbose: bool = False) -> List[Dict[str, Any]]:
    """ripgrepを使用してSwiftコード内の翻訳キーの使用箇所を検索
    
    引数:
        key: 検索する翻訳キー (例: "Hello %@", "%lld minutes")
        verbose: デバッグ出力を有効にする
    
    返り値:
        使用箇所のリスト。各要素は以下の形式:
        [
            {
                'pattern': 'Text',
                'output': '../Alarmify/Features/Home/HomePage.swift:123:        Text("Hello \\(userName)")\\n' +
                         '../Alarmify/Features/Home/HomePage.swift:124:            .font(.title)\\n' +
                         '../Alarmify/Features/Home/HomePage.swift:125:            .foregroundColor(.primary)'
            },
            {
                'pattern': 'String(localized:)',
                'output': '../Alarmify/Utils/Messages.swift:45:    let greeting = String(localized: "Hello \\(name)")\\n' +
                         '../Alarmify/Utils/Messages.swift:46:    return greeting.uppercased()'
            }
        ]
        
        キーが見つからない場合は空のリストを返す。
    """
    pattern = escape_key_for_regex(key)
    results = []
    
    if verbose:
        print(f"    DEBUG: Searching for pattern: {pattern}")
    
    # Text("...")パターンを検索
    text_pattern = f'Text\\("{pattern}"'
    cmd = ['rg', '-n', '-B3', '-A3', '--no-heading', text_pattern, SWIFT_CODE_PATH]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout:
            if verbose:
                print(f"    DEBUG: Found matches with Text pattern")
            results.append({
                'pattern': 'Text',
                'output': result.stdout
            })
    except Exception as e:
        if verbose:
            print(f"    DEBUG: Error searching Text pattern: {e}")
    
    # String(localized: "...")パターンを検索
    string_pattern = f'String\\(localized:\\s*\"{pattern}\"'
    cmd = ['rg', '-n', '-B3', '-A3', '--no-heading', string_pattern, SWIFT_CODE_PATH]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout:
            if verbose:
                print(f"    DEBUG: Found matches with String(localized:) pattern")
            results.append({
                'pattern': 'String(localized:)',
                'output': result.stdout
            })
    except Exception as e:
        if verbose:
            print(f"    DEBUG: Error searching String(localized:) pattern: {e}")
    
    return results

def get_repository_root() -> str:
    """リポジトリのルートディレクトリを取得"""
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()


def add_comment_direct(
    translation_key: str,
    existing_comment: Optional[str] = None,
    verbose: bool = False,
    mode: str = "diff"
) -> bool:
    """
    Claude CLIを使用して直接Localizable.xcstringsにコメントを追加・更新。

    引数:
        translation_key: 分析する英語の翻訳キー
        existing_comment: 既存のコメント（あれば）
        verbose: Trueの場合、詳細なログを有効化
        mode: 処理モード ('diff', 'overwrite', 'reanalyze')

    戻り値:
        処理が成功した場合True
    """

    # まず、Swiftコード内でキーの使用箇所を検索
    usages = find_key_usage(translation_key, verbose)

    if not usages:
        if verbose:
            print(f"    DEBUG: No usage found for key: {translation_key}")
        return False

    # プロンプト用の使用状況コンテキストを準備
    usage_context = []
    for usage in usages:
        usage_context.append(f"=== {usage['pattern']} usage ===")
        usage_context.append(usage['output'].strip())

    usage_text = "\n\n".join(usage_context)

    # モードに応じたプロンプトを作成
    if mode == "reanalyze" and existing_comment:
        prompt = f"""
以下のファイルを直接編集してください:
- Alarmify/Localizable.xcstrings

タスク: 翻訳キーのcommentフィールドを更新してください。

翻訳キー: "{translation_key}"
既存のコメント: "{existing_comment}"

以下の箇所で使用されています：
{usage_text}

上記のコンテキストを元に、既存のコメントと比較して、より適切で詳細な翻訳補助コメントを日本語で作成してください。
既存のコメントより良いコメントがあれば、Localizable.xcstringsの該当キーのcommentフィールドを更新してください。
既存のコメントが十分であれば、変更は不要です。

コメントは1-2文で簡潔に、翻訳の文脈がわかるようにしてください。
        """
    else:
        prompt = f"""
以下のファイルを直接編集してください:
- Alarmify/Localizable.xcstrings

タスク: 翻訳キーにcommentフィールドを追加してください。

翻訳キー: "{translation_key}"

以下の箇所で使用されています：
{usage_text}

上記のコンテキストを元に、翻訳者が適切に翻訳できるよう、日本語で説明的なコメントを作成してください。
Localizable.xcstringsの該当キーにcommentフィールドを追加してください。

コメントは1-2文で簡潔に、翻訳の文脈がわかるようにしてください。

注意: 指定されたキーのcommentフィールドのみを編集し、他のキーや設定は変更しないでください。
        """

    try:
        repo_root = get_repository_root()
        cmd = [
            "claude", "-p", prompt,
            "--add-dir", repo_root,
            "--permission-mode", "acceptEdits",
            "--max-turns", "1000"
        ]

        if verbose:
            print(f"    DEBUG: Executing Claude direct edit...")
            print(f"    DEBUG: Prompt length: {len(prompt)} characters")

        result = subprocess.run(cmd, timeout=600)

        if result.returncode == 0:
            if verbose:
                print(f"    DEBUG: Claude direct edit completed successfully")
            return True
        else:
            print(f"    ERROR: Claude CLI failed with return code {result.returncode}")
            return False

    except subprocess.TimeoutExpired:
        print(f"    ERROR: Claude CLI timed out for key: {translation_key}")
        return False
    except Exception as e:
        print(f"    ERROR: Exception running Claude CLI: {e}")
        return False


def load_localizable_data() -> Dict[str, Any]:
    """Localizable.xcstringsデータを読み込み"""
    if not os.path.exists(LOCALIZABLE_PATH):
        print(f"Error: Localizable.xcstrings not found at {LOCALIZABLE_PATH}")
        sys.exit(1)
    
    with open(LOCALIZABLE_PATH, "r", encoding="utf-8") as file:
        return json.load(file)

def save_localizable_data(data: Dict[str, Any], verbose: bool = False) -> None:
    """Localizable.xcstringsデータを保存"""
    if verbose:
        print(f"DEBUG: Saving data to {LOCALIZABLE_PATH}")
    try:
        with open(LOCALIZABLE_PATH, "w", encoding="utf-8") as file:
            json.dump(data, file, indent=2, ensure_ascii=False, separators=(",", " : "))
        if verbose:
            print(f"DEBUG: Successfully saved data to {LOCALIZABLE_PATH}")
    except Exception as e:
        print(f"ERROR: Failed to save data: {e}")
        raise

def commit_changes(key: str, action: str = "Added", verbose: bool = False) -> bool:
    """コメント追加/更新後にgit commit & pushを実行

    引数:
        key: 翻訳キー（コミットメッセージに使用）
        action: "Added" または "Updated"（コミットメッセージに使用）
        verbose: Trueの場合、詳細なログを有効化

    戻り値:
        コミットが成功した場合True、それ以外はFalse
    """
    try:
        # git add
        subprocess.run(["git", "add", LOCALIZABLE_PATH], check=True)

        # git diff --cached で差分があるかチェック
        diff_result = subprocess.run(
            ["git", "diff", "--cached", "--quiet"],
            capture_output=True
        )

        # 差分がない場合はスキップ（returncode 0 = 差分なし）
        if diff_result.returncode == 0:
            if verbose:
                print(f"  DEBUG: No changes to commit for key: {key}")
            return False

        # git commit（キーが長い場合は50文字で切る）
        truncated_key = key[:50] + "..." if len(key) > 50 else key
        commit_message = f"[skip ci] {action} comment: {truncated_key}"
        subprocess.run(["git", "commit", "-m", commit_message], check=True)

        # git push
        current_branch = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, check=True
        ).stdout.strip()
        subprocess.run(["git", "push", "-u", "origin", current_branch], check=True)

        print(f"  Committed and pushed: {commit_message}")
        return True

    except subprocess.CalledProcessError as e:
        print(f"  Warning: Failed to commit/push for key '{key}': {e}")
        return False

def is_translation_stale(value: Dict[str, Any]) -> bool:
    """extractionStateがstaleかどうかをチェック"""
    return value.get("extractionState") == "stale"

def main():
    parser = argparse.ArgumentParser(description="Add translation helper comments to Localizable.xcstrings")
    parser.add_argument(
        "--mode",
        choices=["diff", "overwrite", "reanalyze"],
        default="diff",
        help="Mode: diff (default, only add missing comments), overwrite (overwrite all), reanalyze (review and fix inappropriate comments)"
    )
    parser.add_argument(
        "-n", "--max-translations",
        type=int,
        help="Maximum number of translations to process (default: unlimited)"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose logging output"
    )

    args = parser.parse_args()

    # スクリプトディレクトリに移動
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.verbose:
        print(f"DEBUG: Script directory: {script_dir}")
        print(f"DEBUG: Current working directory before change: {os.getcwd()}")
    os.chdir(script_dir)
    if args.verbose:
        print(f"DEBUG: Current working directory after change: {os.getcwd()}")

    # ファイルが存在するかチェック
    if args.verbose:
        print(f"DEBUG: Checking if LOCALIZABLE_PATH exists: {LOCALIZABLE_PATH}")
        print(f"DEBUG: Absolute path to LOCALIZABLE_PATH: {os.path.abspath(LOCALIZABLE_PATH)}")
        print(f"DEBUG: File exists: {os.path.exists(LOCALIZABLE_PATH)}")

        print(f"DEBUG: Checking if SWIFT_CODE_PATH exists: {SWIFT_CODE_PATH}")
        print(f"DEBUG: Absolute path to SWIFT_CODE_PATH: {os.path.abspath(SWIFT_CODE_PATH)}")
        print(f"DEBUG: Directory exists: {os.path.exists(SWIFT_CODE_PATH)}")

    print(f"Running in mode: {args.mode}")
    print(f"Using Claude CLI (direct edit mode)")

    print(f"Loading Localizable.xcstrings...")
    if args.verbose:
        print(f"  Path: {LOCALIZABLE_PATH}")

    # データを読み込み
    data = load_localizable_data()

    # 翻訳すべきでないキーをスキップ
    skip_keys = ["", " - ", " / ", "- ", ",", ":", "\n", " "]

    strings = data.get("strings", {})
    total_keys = len(strings)
    processed_keys = 0
    success_count = 0
    translation_count = 0  # 実際に処理された翻訳の数を追跡

    print(f"Found {total_keys} translation keys")
    if args.max_translations:
        print(f"Will process maximum {args.max_translations} translations")

    for key, value in strings.items():
        processed_keys += 1
        print(f"Processing [{processed_keys}/{total_keys}]: {key[:50]}...")

        # 特定のキーをスキップ
        if key in skip_keys:
            print(f"  Skipping: key in skip list")
            continue

        # shouldTranslateがfalseの場合はスキップ
        if value.get("shouldTranslate") is False:
            print(f"  Skipping: shouldTranslate is false")
            continue

        # 翻訳がstaleの場合はスキップ
        if is_translation_stale(value):
            print(f"  Skipping: translation is stale")
            continue

        # 日本語翻訳があるかチェック
        ja_translation = (
            value.get("localizations", {})
            .get("ja", {})
            .get("stringUnit", {})
            .get("value", "")
        )

        if not ja_translation:
            print(f"  Skipping: no Japanese translation")
            continue

        # 翻訳の上限に達したかチェック
        if args.max_translations and translation_count >= args.max_translations:
            print(f"  Reached translation limit ({args.max_translations}), stopping...")
            break

        existing_comment = value.get("comment", "")

        # モード別の処理
        if args.mode == "diff":
            # コメントが存在しない場合のみ追加
            if existing_comment:
                print(f"  Skipping: comment already exists")
                continue

            print(f"  Adding comment with Claude direct edit...")
            translation_count += 1
            success = add_comment_direct(key, verbose=args.verbose, mode="diff")

            if success:
                success_count += 1
                print(f"  Successfully added comment")
                # Claudeが直接編集するため、コミットのみ実行
                commit_changes(key, action="Added", verbose=args.verbose)
            else:
                print(f"  Failed to add comment (key may not be found in code)")

        elif args.mode == "overwrite":
            # すべてのコメントを上書き
            print(f"  Overwriting comment with Claude direct edit...")
            translation_count += 1
            success = add_comment_direct(key, verbose=args.verbose, mode="overwrite")

            if success:
                success_count += 1
                action = "Updated" if existing_comment else "Added"
                print(f"  Successfully {action.lower()} comment")
                commit_changes(key, action=action, verbose=args.verbose)
            else:
                print(f"  Failed to update comment (key may not be found in code)")

        elif args.mode == "reanalyze":
            # 不適切なコメントを再分析して修正
            print(f"  Reanalyzing comment with Claude direct edit...")
            translation_count += 1
            success = add_comment_direct(
                key,
                existing_comment=existing_comment if existing_comment else None,
                verbose=args.verbose,
                mode="reanalyze"
            )

            if success:
                success_count += 1
                action = "Updated" if existing_comment else "Added"
                print(f"  Successfully {action.lower()} comment")
                commit_changes(key, action=action, verbose=args.verbose)
            else:
                print(f"  Failed to analyze comment (key may not be found in code)")

    # 最終確認
    if args.verbose:
        print(f"\nDEBUG: Final verification...")
        try:
            with open(LOCALIZABLE_PATH, "r", encoding="utf-8") as file:
                saved_data = json.load(file)

            # 実際にコメントを持つキーの数をカウント
            comment_count = 0
            for key, value in saved_data.get("strings", {}).items():
                if value.get("comment"):
                    comment_count += 1

            print(f"DEBUG: File now contains {comment_count} keys with comments")
        except Exception as e:
            print(f"ERROR: Failed to verify file save: {e}")

    print(f"\nCompleted!")
    print(f"  Total keys processed: {processed_keys}")
    print(f"  Translations processed: {translation_count}")
    print(f"  Successful operations: {success_count}")
    if args.max_translations and translation_count >= args.max_translations:
        print(f"  Processing stopped after reaching limit of {args.max_translations} translations")
    print(f"  Updated file: {os.path.abspath(LOCALIZABLE_PATH)}")

if __name__ == "__main__":
    main()
