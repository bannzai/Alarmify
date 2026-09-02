#!/bin/bash
# Release ビルドで RevenueCat の実キー (appl_ で始まる public API key) が設定されていることを検査する。
# Alarmify ターゲットの Build Phase (Run Script) から呼ぶ。
#
# Test Store のキー (test_) や空のキーのまま App Store 向けのバイナリを作ると、
# 出荷後に購入・復元が動かないことに気づけないため、ビルドエラーで止める。
# 参照: Config.xcconfig のコメント (キーの置き場所と取得方法)
#
# 冪等: 環境変数 CONFIGURATION / REVENUECAT_API_KEY を読み取って判定するだけで、副作用を持たない
set -euo pipefail

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

case "${REVENUECAT_API_KEY:-}" in
  appl_*)
    exit 0
    ;;
  "")
    echo "error: Release ビルドに RevenueCat の API key がありません。Config.local.xcconfig に REVENUECAT_API_KEY = appl_... を書いてください (Config.xcconfig のコメント参照)" >&2
    exit 1
    ;;
  *)
    echo "error: Release ビルドの REVENUECAT_API_KEY が appl_ で始まっていません。App Store 向けには Test Store ではなく App Store 用の public API key を使ってください" >&2
    exit 1
    ;;
esac
