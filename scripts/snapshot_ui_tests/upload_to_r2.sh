#!/usr/bin/env bash
#
# upload_to_r2.sh - Upload files to Cloudflare R2 using AWS Signature V4
#
# 【概要】
# Cloudflare R2にファイルをアップロードするスクリプト。
# curlの --aws-sigv4 オプションを使用してAWS Signature Version 4で認証します。
#
# 【必要な環境変数】
# - R2_ACCOUNT_ID: CloudflareアカウントID
# - R2_ACCESS_KEY_ID: R2 APIトークンのAccess Key ID
# - R2_SECRET_ACCESS_KEY: R2 APIトークンのSecret Access Key
# - R2_BUCKET_NAME: アップロード先のR2バケット名
# - R2_PUBLIC_URL: R2バケットの公開URL (例: https://pub-xxxxx.r2.dev)
#
# 【使い方】
# 1. 環境変数を設定:
#    export R2_ACCOUNT_ID='your_account_id'
#    export R2_ACCESS_KEY_ID='your_access_key_id'
#    export R2_SECRET_ACCESS_KEY='your_secret_access_key'
#    export R2_BUCKET_NAME='your_bucket_name'
#    export R2_PUBLIC_URL='https://pub-xxxxx.r2.dev'
#
# 2. スクリプトから関数として読み込んで使用:
#    source scripts/snapshot_ui_tests/upload_to_r2.sh
#    upload_to_r2 "/path/to/file.png" "screenshots/test/file.png"
#    echo $?  # 0=成功, 1=失敗
#
# 3. コマンドラインから直接実行:
#    ./scripts/snapshot_ui_tests/upload_to_r2.sh /path/to/file.png screenshots/test/file.png
#    # HTTPステータスコードが最終行に出力されます (200=成功)
#
# 【引数】
# $1: file_path - アップロードするローカルファイルのパス
# $2: object_key - R2バケット内のオブジェクトキー（パス）
#
# 【戻り値】
# 0: アップロード成功 (HTTP 200)
# 1: アップロード失敗 (環境変数未設定、curlエラー、HTTP 200以外)
#
# 【出力】
# 標準出力: curlのレスポンス + 最終行にHTTPステータスコード
# 標準エラー: エラーメッセージ
#
# 【例】
# # 画像をアップロード
# ./scripts/snapshot_ui_tests/upload_to_r2.sh screenshot.png screenshots/2025/01/19/test.png
#
# # 成功時の出力例:
# 200
#
# # 失敗時の出力例 (stderr):
# Error: R2_ACCOUNT_ID environment variable is not set
#
# 【必要なツール】
# - curl 7.75+ (--aws-sigv4 サポート必須)
#   macOSの場合: brew install curl
#
# 【参考】
# - Cloudflare R2 ドキュメント: https://developers.cloudflare.com/r2/
# - AWS Signature Version 4: https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
#

set -euo pipefail

upload_to_r2() {
  local file_path="$1"
  local object_key="$2"

  # 環境変数チェック
  if [ -z "${R2_ACCOUNT_ID:-}" ]; then
    echo "Error: R2_ACCOUNT_ID environment variable is not set" >&2
    return 1
  fi
  if [ -z "${R2_ACCESS_KEY_ID:-}" ]; then
    echo "Error: R2_ACCESS_KEY_ID environment variable is not set" >&2
    return 1
  fi
  if [ -z "${R2_SECRET_ACCESS_KEY:-}" ]; then
    echo "Error: R2_SECRET_ACCESS_KEY environment variable is not set" >&2
    return 1
  fi
  if [ -z "${R2_BUCKET_NAME:-}" ]; then
    echo "Error: R2_BUCKET_NAME environment variable is not set" >&2
    return 1
  fi

  # ファイル存在チェック
  if [ ! -f "$file_path" ]; then
    echo "Error: File not found: $file_path" >&2
    return 1
  fi

  local endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  local url="${endpoint}/${R2_BUCKET_NAME}/${object_key}"

  # curl の --aws-sigv4 が使えるかチェック
  if ! curl --help all 2>/dev/null | grep -q -- "--aws-sigv4"; then
    echo "Error: your curl does not support --aws-sigv4" >&2
    echo "       Please update curl (7.75+ required) or install via Homebrew: brew install curl" >&2
    return 1
  fi

  # 認証情報を argv に載せると同一ホストの他プロセスから ps 等で読めるため、
  # 0600 の一時 curl 設定ファイル経由で渡し、リクエスト後に削除する
  local curl_config
  curl_config=$(mktemp) || return 1
  chmod 600 "$curl_config"
  printf 'user = "%s:%s"\n' "$R2_ACCESS_KEY_ID" "$R2_SECRET_ACCESS_KEY" > "$curl_config"

  # アップロード実行。接続 10 秒・全体 120 秒で打ち切る (ハングした転送で撮影フロー全体を止めないための上限)
  local response
  response=$(curl -s -w "\n%{http_code}" -X PUT "$url" \
    --connect-timeout 10 \
    --max-time 120 \
    --aws-sigv4 "aws:amz:auto:s3" \
    --config "$curl_config" \
    -H "Content-Type: image/png" \
    --data-binary "@${file_path}")
  local curl_status=$?
  rm -f "$curl_config"

  echo "$response"
  # curl は 403/500 でも exit 0 を返すため、最終行の HTTP ステータスでも成否を判定する
  if [ $curl_status -ne 0 ] || [ "$(echo "$response" | tail -n1)" != "200" ]; then
    return 1
  fi
  return 0
}

# コマンドラインから直接実行された場合
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  if [ $# -ne 2 ]; then
    echo "Usage: $0 <file_path> <object_key>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 /path/to/image.png screenshots/2025/01/19/image.png" >&2
    echo "" >&2
    echo "Required environment variables:" >&2
    echo "  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME" >&2
    exit 1
  fi

  # upload_to_r2 は curl の exit code と HTTP ステータス (非 200) の両方を検査して返す
  if upload_to_r2 "$1" "$2"; then
    exit 0
  else
    exit 1
  fi
fi
