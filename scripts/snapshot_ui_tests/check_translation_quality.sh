#!/usr/bin/env bash
#
# check_translation_quality.sh
#
# 【目的】
# スクリーンショットを使用して翻訳品質をチェックし、問題があればGitHub Issueを自動作成
# ja.pngを基準として、他言語の翻訳が適切かをAI CLI (Codex/Claude)で判断
#
# 【プロセス分離の理由】
# Claude/Codexで問題を分析する際に、変更内容の出力とgh issue createを同時に実行できない。
# そのため、このスクリプトは2ステップに分かれている:
#   1. AI分析フェーズ: 問題を発見してissue_mdファイルを作成
#   2. Issue作成フェーズ: issue_mdファイルからgh issue createを実行
#
# 【使い方】
# 1. 全てのスクリーンショットをチェック (Codex CLI使用):
#    $ ./scripts/snapshot_ui_tests/check_translation_quality.sh
#
# 2. Claude CLIを使用してチェック:
#    $ ./scripts/snapshot_ui_tests/check_translation_quality.sh --use-claude
#
# 3. 最初のN個のテストのみチェック (デバッグ用):
#    $ ./scripts/snapshot_ui_tests/check_translation_quality.sh -n 3
#
# 4. Issue作成をスキップしてチェックのみ:
#    $ ./scripts/snapshot_ui_tests/check_translation_quality.sh --dry-run
#
# 5. ヘルプを表示:
#    $ ./scripts/snapshot_ui_tests/check_translation_quality.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

SCREENSHOTS_DIR="scripts/snapshot_ui_tests/screenshots"

# upload_to_r2.sh を読み込み
source "${SCRIPT_DIR}/upload_to_r2.sh"

# GitHub Issue テンプレート
ISSUE_TEMPLATE='---
title: "翻訳品質改善: {{FEATURE_PAGE}} - {{LANG}} (Index: {{INDEX}})"
labels: translation,i18n,quality
---

## 問題のあるスクリーンショット
- Feature: {{FEATURE_PAGE}}
- Index: {{INDEX}}
- Language: {{LANG}}

## スクリーンショット
- 基準（日本語）: scripts/snapshot_ui_tests/screenshots/{{FEATURE_PAGE}}/{{INDEX}}/ja.png
- 問題のある翻訳: scripts/snapshot_ui_tests/screenshots/{{FEATURE_PAGE}}/{{INDEX}}/{{LANG}}.png

## ソースコード
- パス: {{SOURCE_PATH}}

## 問題の詳細
Claudeによる分析結果をここに記載してください。

## 修正方針
Claudeが提案する修正方針をここに記載してください。

## チェックリスト
- [ ] 翻訳ファイルの特定
- [ ] 適切な翻訳への修正
- [ ] UIテストで確認
- [ ] スクリーンショット再生成'

# オプション解析
MAX_ISSUES=""
DRY_RUN=false
USE_CLAUDE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      MAX_ISSUES="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --use-claude)
      USE_CLAUDE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -n N               作成するIssue数の上限 (デフォルト: 全て)"
      echo "  --dry-run          Issue作成せずにチェックのみ実行"
      echo "  --use-claude       Claude CLIを使用 (デフォルト: Codex CLI)"
      echo "  -h, --help         このヘルプメッセージを表示"
      echo ""
      echo "Examples:"
      echo "  # 全言語をチェック (Codex CLI)"
      echo "  $0"
      echo ""
      echo "  # Claude CLIを使用"
      echo "  $0 --use-claude"
      echo ""
      echo "  # 最初の3個のIssueだけ作成"
      echo "  $0 -n 3"
      echo ""
      echo "  # Dry run（Issue作成なし）"
      echo "  $0 --dry-run"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# 進行ログを見やすく
sep() { printf '\n==== %s ====\n' "$*"; }

# カンマ区切りの label がリポジトリに揃っているか確認し、無いものは作る (再実行しても既存は変更しない)
ensure_labels() {
  local labels=$1
  local existing
  existing=$(gh label list --limit 200 --json name --jq '.[].name')
  local label
  for label in $(echo "$labels" | tr ',' '\n'); do
    [ -n "$label" ] || continue
    if ! echo "$existing" | grep -qx "$label"; then
      gh label create "$label" --description "翻訳品質チェック (scripts/snapshot_ui_tests/check_translation_quality.sh) が起票する Issue" --color "0E8A16" || \
        echo "    Warning: label '$label' を作成できませんでした"
    fi
  done
}

# GitHub Issueに画像をアップロードする関数
# Cloudflare R2 (AWS Signature V4認証) + ライフサイクルポリシーで30日後自動削除
upload_screenshot_to_issue() {
  local issue_number="$1"
  local ja_png="$2"
  local lang_png="$3"
  local feature_page="$4"
  local index="$5"

  echo "    Uploading screenshots to issue #$issue_number via Cloudflare R2..."

  # 必要な環境変数を確認
  if [ -z "${R2_PUBLIC_URL:-}" ]; then
    echo "    Error: R2_PUBLIC_URL environment variable is not set"
    return 1
  fi

  # ユニークなファイル名を生成
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local ja_key="screenshots/${feature_page}/${index}/${timestamp}-ja.png"
  local lang_key="screenshots/${feature_page}/${index}/${timestamp}-$(basename "$lang_png")"

  # 日本語スクリーンショットをアップロード (upload_to_r2.sh の関数を使用)
  echo "    Uploading ja.png..."
  local ja_response=$(upload_to_r2 "$ja_png" "$ja_key")
  local ja_http_code=$(echo "$ja_response" | tail -n1)

  if [ "$ja_http_code" != "200" ]; then
    echo "    Error: Failed to upload ja.png (HTTP ${ja_http_code})"
    echo "    Response: $(echo "$ja_response" | head -n-1)"
    return 1
  fi

  local ja_url="${R2_PUBLIC_URL}/${ja_key}"
  echo "    ja.png uploaded: $ja_url"

  # 問題のある言語のスクリーンショットをアップロード
  echo "    Uploading ${lang_png##*/}..."
  local lang_response=$(upload_to_r2 "$lang_png" "$lang_key")
  local lang_http_code=$(echo "$lang_response" | tail -n1)

  if [ "$lang_http_code" != "200" ]; then
    echo "    Error: Failed to upload ${lang_png##*/} (HTTP ${lang_http_code})"
    echo "    Response: $(echo "$lang_response" | head -n-1)"
    return 1
  fi

  local lang_url="${R2_PUBLIC_URL}/${lang_key}"
  echo "    ${lang_png##*/} uploaded: $lang_url"

  # Issue本文に画像を追加（テーブル形式、imgタグでwidth=320指定）
  echo "    Adding images to issue..."
  gh issue comment "$issue_number" --body "## スクリーンショット比較

| 基準（日本語） | 問題のある翻訳 (${lang_png##*/}) |
|:---:|:---:|
| <img src=\"${ja_url}\" width=\"320\"> | <img src=\"${lang_url}\" width=\"320\"> |

---
*スクリーンショットはCloudflare R2に自動的にアップロードされました（30日後に自動削除）*" || {
    echo "    Warning: Failed to add image comment to issue #$issue_number"
    return 1
  }

  echo "    Successfully added images to issue #$issue_number"
  return 0
}

sep "Starting translation quality check"

if [ ! -d "$SCREENSHOTS_DIR" ]; then
  echo "Error: Screenshots directory not found: $SCREENSHOTS_DIR"
  echo "Please run generate_snapshot_ui_test_screenshots.sh first"
  exit 1
fi

# 期待する Feature Page (テストクラス) の一覧は AlarmifySnapshotUITests/**/*SnapshotUITest.swift が SSOT。
# 実在するディレクトリだけを走査すると、-n 1 で一部しか生成していない状態を全件チェック済みと誤認するため、
# 期待側から辿って出力ディレクトリの欠落を失敗として収集する
feature_pages=$(find AlarmifySnapshotUITests -type f -name "*SnapshotUITest.swift" -exec basename {} .swift \; | sort)

# echo は空文字でも改行を出して wc -l が 1 になるため、件数ではなく変数の空判定で 0 件を検出する
if [ -z "$feature_pages" ]; then
  echo "Error: AlarmifySnapshotUITests に SnapshotUITest が見つかりません"
  exit 1
fi
total_features=$(echo "$feature_pages" | wc -l | tr -d ' ')

# 比較対象の言語 (ja 以外) は撮影言語の SSOT (AlarmifySnapshotUITests/Languages.swift) から決める。
# ディレクトリに実在する PNG だけを比較すると、-l ja だけで生成した状態を「問題なし」と誤認するため
expected_langs=$(sed -nE 's/^[[:space:]]*\("([A-Za-z-]+)",.*/\1/p' AlarmifySnapshotUITests/Languages.swift | grep -v '^ja$' || true)
if [ -z "$expected_langs" ]; then
  echo "Error: AlarmifySnapshotUITests/Languages.swift から比較対象の言語を取得できません"
  exit 1
fi

sep "Found $total_features feature pages"

# -n オプションのメッセージ表示
if [ -n "$MAX_ISSUES" ]; then
  sep "Limiting to first $MAX_ISSUES issues"
fi

feature_count=0
check_count=0
issue_count=0
analysis_failures=""
issue_creation_failures=""
missing_baselines=""
missing_comparisons=""

# 繰り返しのupload処理では途中でエラーが起きても処理は継続して欲しい
set +e
for feature_page in $feature_pages; do
  feature_count=$((feature_count + 1))
  feature_page_dir="$SCREENSHOTS_DIR/$feature_page"

  sep "[$feature_count/$total_features] Processing: $feature_page"

  if [ ! -d "$feature_page_dir" ]; then
    echo "  Error: スクリーンショットのディレクトリがありません: $feature_page_dir"
    missing_baselines+="  - ${feature_page} (directory missing)"$'\n'
    continue
  fi

  # README.mdからソースパスを取得
  readme_file="$feature_page_dir/README.md"
  if [ ! -f "$readme_file" ]; then
    echo "Warning: README.md not found, skipping $feature_page"
    continue
  fi
  
  source_path=$(grep -E '^`.*`$' "$readme_file" | sed 's/`//g' | head -1)
  echo "Source path: $source_path"

  # 期待する Preview の個数はテストファイルの `let previewCount = N` が SSOT。
  # 実在するディレクトリだけを走査すると、中断で欠けたインデックスを未検査のまま成功にしてしまうため、
  # 0..N-1 を期待側から辿り、無いインデックスは基準画像の欠落として収集する
  test_source=$(find AlarmifySnapshotUITests -type f -name "${feature_page}.swift" 2>/dev/null | head -1)
  preview_count=1
  if [ -n "$test_source" ]; then
    preview_count=$(sed -nE 's/^[[:space:]]*let previewCount = ([0-9]+).*/\1/p' "$test_source" | head -1)
    preview_count=${preview_count:-1}
  fi

  for ((index = 0; index < preview_count; index++)); do
    index_dir="$feature_page_dir/$index"
    if [ ! -d "$index_dir" ]; then
      echo "  Error: Index $index のスクリーンショットがありません: $index_dir"
      missing_baselines+="  - ${feature_page}/${index}"$'\n'
      continue
    fi

    sep "  Index: $index"

    # ja.pngが存在するか確認。基準画像の欠落をスキップ (成功扱い) にすると
    # 「比較言語だけ生成した状態でのチェック未実施」を問題なしと誤認するため、失敗として収集する
    ja_png="$index_dir/ja.png"
    if [ ! -f "$ja_png" ]; then
      echo "  Error: ja.png (基準画像) がありません: $index_dir"
      missing_baselines+="  - ${feature_page}/${index}"$'\n'
      continue
    fi

    echo "  Base image: $ja_png"

    # 各言語をチェック。対象言語の PNG が無ければ、比較を飛ばさず欠落として収集する
    for lang in $expected_langs; do
      if [ ! -f "$index_dir/${lang}.png" ]; then
        echo "  Error: ${lang}.png (比較画像) がありません: $index_dir"
        missing_comparisons+="  - ${feature_page}/${index}/${lang}"$'\n'
        continue
      fi
      # Issue数の上限チェック
      if [ -n "$MAX_ISSUES" ] && [ "$issue_count" -ge "$MAX_ISSUES" ]; then
        sep "Reached maximum issue limit ($MAX_ISSUES), stopping"
        break 3  # 3層のループを抜ける（言語、index、feature_page）
      fi

      check_count=$((check_count + 1))
      lang_png="$index_dir/${lang}.png"

      sep "    Checking: $lang ($ja_png vs $lang_png)"

      # Issue テンプレートのプレースホルダーを置換
      current_issue_template="${ISSUE_TEMPLATE//\{\{FEATURE_PAGE\}\}/$feature_page}"
      current_issue_template="${current_issue_template//\{\{INDEX\}\}/$index}"
      current_issue_template="${current_issue_template//\{\{LANG\}\}/$lang}"
      current_issue_template="${current_issue_template//\{\{SOURCE_PATH\}\}/$source_path}"

      # issue.mdのパス
      issue_md_path="$index_dir/issue-${lang}.md"
      # すでにあるものは削除
      rm -f $issue_md_path

      # Claude CLIでチェック
      prompt="翻訳品質チェックをお願いします。

## 対象
- 基準画像: scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/ja.png
- 比較画像: scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/${lang}.png

## 確認ポイント
このアプリは日本語が正しい表現になっています。ja.pngを正として、${lang}.pngの翻訳が適切かを判断してください。

## 参考情報
- ソースコード: ${source_path}
- 文書: ${source_path}/README.md も参考にしてください

## 翻訳の問題がある場合の判断基準
- 文脈に合わない翻訳
- 用語の不統一
- 文字切れ・表示崩れ
- 未翻訳（日本語のまま）
- 不自然な表現

## 判定対象外: 外部サービスから送られる値
アラームのタイトル (「デプロイ完了」「センサー検知」等) は外部サービスが API で送ってくる
自由テキストで、Preview のサンプルデータとして日本語のまま保存されています。
ローカライズ対象ではないため、どの言語のスクリーンショットに日本語のアラームタイトルが
写っていても「未翻訳」と判定しないでください。
API のエンドポイント・JSON のキー名・トークン文字列も同様に判定対象外です。
判定対象は UI 側の文言 (ラベル・ボタン・見出し・注釈) だけです。

## 重要な注意事項

### 1. 日付・時刻・ロケール依存表示について
日付や時刻の表記 (例: 「2026年8月16日」と「Aug 16, 2026」) はロケールに応じてシステムが整形するもので、順序や区切りが言語ごとに異なるのは仕様です。翻訳の問題として指摘しないでください。

### 2. 翻訳の影響範囲について
翻訳文字列は複数の箇所で再利用される可能性があります。特定の画面だけでなく、他の箇所でも同じ翻訳キーが使用されることを考慮してください。

例：「I did」(やれた) という文字列は夜の振り返りとジャーナルの両方で使われており、片方の画面に合わせて意味を変えると、もう片方の画面の意味も変わってしまいます。

**修正を提案する際は、必ず以下を確認してください：**
- その翻訳キーが他の箇所でも使用される可能性
- 修正が他の画面やコンテキストでも適切かどうか
- 文脈に依存する翻訳の場合は、別の翻訳キーを使用するよう提案すること

## 問題があった場合の対応
scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/issue-${lang}.md を作成してください。

### Issue ファイルのフォーマット
以下のフォーマットでMarkdownファイルを作成してください:

\`\`\`markdown
---
title: \"翻訳品質改善: ${feature_page} - ${lang} (Index: ${index})\"
labels: translation,i18n,quality
---

## 問題のあるスクリーンショット
- Feature: ${feature_page}
- Index: ${index}
- Language: ${lang}

## スクリーンショット
- 基準（日本語）: scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/ja.png
- 問題のある翻訳: scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/${lang}.png

## ソースコード
- パス: ${source_path}

## 問題の詳細
(ここに具体的な問題を記載してください。スクリーンショットの該当箇所を明示してください。)

## 修正方針
(ここに修正方針を記載してください。推奨される翻訳があれば提案してください。)

## チェックリスト
- [ ] 翻訳ファイルの特定
- [ ] 適切な翻訳への修正
- [ ] UIテストで確認
- [ ] スクリーンショット再生成
\`\`\`

### 注意事項
- 問題の詳細と修正方針は具体的に記載してください
- スクリーンショットの該当箇所を明示してください
- 推奨される翻訳があれば提案してください
- ファイルパスは必ず scripts/snapshot_ui_tests/screenshots/${feature_page}/${index}/issue-${lang}.md にしてください

## 問題がない場合
issue-${lang}.md ファイルは作成せず、「翻訳に問題は見つかりませんでした」と報告してください。繰り返しますが、問題が無いのならissue-${lang}.mdは作成しないでください"

      # 翻訳分析は dry-run でも実行する (dry-run は Issue 作成・画像アップロードだけを省略する)。
      # AI CLI の失敗 (認証切れ・API 障害・CLI 不在等) を「問題なし」と混同しないよう収集し、最後に非ゼロで終了する
      if [ "$USE_CLAUDE" = true ]; then
        echo "    Running Claude CLI..."
        # Claude CLI実行
        if ! claude \
          --permission-mode acceptEdits \
          --max-turns 20 \
          --add-dir . \
          -p "$prompt"; then
          analysis_failures+="  - ${feature_page}/${index}/${lang} (claude)"$'\n'
          echo "    Error: Claude CLI failed for ${feature_page}/${index}/${lang}"
          continue
        fi
        echo "    Claude CLI check completed"
      else
        echo "    Running Codex CLI..."
        # Codex CLI実行（画像を含む）
        # NOTE: --image で画像を渡すとハングするので一旦諦めた。パスをpromptで渡してもうまく動く
        # NOTE: --full-auto は codex-cli 0.147.0 で廃止されたため付けない (exec は元々非対話実行)
        # stdin をパイプのままにすると codex が追加入力を待ってハングするため /dev/null を与える
        if ! codex exec "$prompt" \
          --sandbox workspace-write < /dev/null; then
          analysis_failures+="  - ${feature_page}/${index}/${lang} (codex)"$'\n'
          echo "    Error: Codex CLI failed for ${feature_page}/${index}/${lang}"
          continue
        fi
        echo "    Codex CLI check completed"
      fi

      if [ "$DRY_RUN" = true ]; then
        # dry-run: 分析結果 (issue.md の有無) の報告のみ行い、Issue 作成・画像アップロードは省略する
        if [ -f "$issue_md_path" ]; then
          echo "    [DRY RUN] Issue file created (not submitted): $issue_md_path"
          issue_count=$((issue_count + 1))
        else
          echo "    [DRY RUN] No issues found (issue.md not created)"
        fi
      else
        # issue.mdが作成されたかチェック
        if [ -f "$issue_md_path" ]; then
          echo "    Issue file created: $issue_md_path"

          # GitHub Issueを作成。同じ対象の open Issue が既にある場合は重複作成しない (再実行の冪等性)。
          # 重複確認そのものが失敗 (API 障害・認証切れ) した時は「該当なし」と区別し、重複を作らないよう起票を見送って失敗に数える
          issue_title="翻訳品質改善: ${feature_page} - ${lang} (Index: ${index})"
          if ! existing_issue=$(gh issue list --state open --label translation --search "in:title \"${issue_title}\"" --json number --jq '.[0].number // empty'); then
            echo "    Error: 既存 Issue の確認に失敗しました (gh issue list)。重複を避けるため起票を見送ります"
            echo "    Issue file preserved at: $issue_md_path"
            issue_creation_failures+="  - ${feature_page}/${index}/${lang} (duplicate lookup failed)"$'\n'
            sleep 2
            continue
          fi
          if [ -n "$existing_issue" ]; then
            echo "    Skipping issue creation (open issue #${existing_issue} already exists): $issue_title"
            issue_count=$((issue_count + 1))
            sleep 2
            continue
          fi
          # issue.md の front matter (title / labels) は gh には解釈されないため、labels を取り出して --label で渡し、
          # 本文からは front matter を取り除く。label はリポジトリに無ければ作る (無い label を渡すと起票が失敗する)
          issue_labels=$(sed -nE 's/^labels:[[:space:]]*//p' "$issue_md_path" | head -1 | tr -d ' ')
          issue_labels=${issue_labels:-translation,i18n,quality}
          ensure_labels "$issue_labels"
          issue_body_path="${issue_md_path%.md}.body.md"
          awk 'NR == 1 && $0 == "---" { skipping = 1; next } skipping && $0 == "---" { skipping = 0; next } !skipping { print }' "$issue_md_path" > "$issue_body_path"
          sep "    Creating GitHub Issue from $issue_md_path"
          if ! issue_url=$(gh issue create \
            --title "$issue_title" \
            --label "$issue_labels" \
            --body-file "$issue_body_path"); then
            # 検出済みの問題を Issue にできなかった場合は成功扱いにしない (最後に非ゼロで終了する)
            echo "    Error: Failed to create GitHub Issue"
            echo "    Issue file preserved at: $issue_md_path"
            issue_creation_failures+="  - ${feature_page}/${index}/${lang}"$'\n'
            sleep 2
            continue
          fi

          if [ -n "$issue_url" ]; then
            echo "    Issue created: $issue_url"
            # Issue番号を抽出してコメントを追加
            issue_number=$(echo "$issue_url" | grep -oE '[0-9]+$')
            if [ -n "$issue_number" ]; then
              # 画像をIssueにアップロード
              if upload_screenshot_to_issue "$issue_number" "$ja_png" "$lang_png" "$feature_page" "$index"; then
                echo "    Successfully uploaded screenshots to issue #$issue_number"
              else
                echo "    Warning: Failed to upload screenshots, but continuing..."
              fi

              echo "    Adding @claude comment to issue #$issue_number"
              gh issue comment "$issue_number" --body "@claude" || {
                echo "    Warning: Failed to add comment to issue #$issue_number"
              }
            fi
          fi

          issue_count=$((issue_count + 1))
        else
          echo "    No issues found (issue.md not created)"
        fi
      fi

      # 次のチェックまで少し待機（API制限対策）
      sleep 2
    done
  done
done
set -e

sep "Translation quality check complete"
echo "CLI used: $([ "$USE_CLAUDE" = true ] && echo "Claude" || echo "Codex")"
echo "Total feature pages: $total_features"
echo "Total checks performed: $check_count"
check_failed=false
if [ -n "$analysis_failures" ]; then
  sep "ERROR: The following comparisons could not be analyzed:"
  echo "$analysis_failures"
  check_failed=true
fi
if [ -n "$missing_baselines" ]; then
  sep "ERROR: Baseline (ja.png) missing for:"
  echo "$missing_baselines"
  echo "先に generate_snapshot_ui_test_screenshots.sh で ja を含めて生成してください"
  check_failed=true
fi
if [ -n "$missing_comparisons" ]; then
  sep "ERROR: Comparison image missing for:"
  echo "$missing_comparisons"
  echo "先に generate_snapshot_ui_test_screenshots.sh で対象言語 (AlarmifySnapshotUITests/Languages.swift) をすべて生成してください"
  check_failed=true
fi
if [ -n "$issue_creation_failures" ]; then
  sep "ERROR: GitHub Issue creation failed for:"
  echo "$issue_creation_failures"
  check_failed=true
fi
if [ "$check_failed" = true ]; then
  echo "未実施・未起票の検出結果を「問題なし」と扱わないため、非ゼロで終了します"
  exit 1
fi
if [ "$DRY_RUN" = false ]; then
  echo "Issues potentially created: $issue_count"
  echo ""
  echo "Note: Actual issue count depends on AI analysis"
  echo "Check GitHub Issues: gh issue list --label translation"
else
  echo "[DRY RUN] No issues were created"
fi
