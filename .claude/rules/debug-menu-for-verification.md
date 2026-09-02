# 検証用の状態作り込みは開発者メニューで行う

動作確認・E2E テストで到達困難な状態 (サンプルデータ投入・課金状態・push 到着のシミュレート等) を作る時は、起動引数・環境変数ではなく、アプリ内の開発者メニューに操作を追加する。取り込み元: bannzai/mementomorning の同名ルール (経緯: https://github.com/bannzai/castle/issues/487 )。

## 理由

- 起動引数はリモート simulator (simtunnel) に渡せず、実機でも扱いにくい。開発者メニューは mobile-mcp 互換ツールのタップで操作でき、simulator・実機・リモートのどの経路でも同じ手順で状態を作れ、E2E テストにそのまま流用できる

## ルール

- 開発者メニューの導線と検証用フラグの効果は DEBUG / TestFlight 配布判定でゲートし、App Store 配布では解放しない (TestFlight は App Store と同一の Release バイナリのため `#if DEBUG` だけでは提供できない。判定方式は mementomorning の ADR 0004 を参考にする)
- 操作要素には `accessibilityIdentifier` (`debug_` prefix) を付与する (Maestro / mobile-mcp からの検出用)
- デバッグ操作は冪等にする (再実行してもデータが壊れない)
- push 経路の検証は開発者メニューより `xcrun simctl push` と `documents/push-payloads/` の payload を優先する (AGENTS.md「検証方法」)
- 実装パターンの詳細は debug-function skill (パターンカタログ・SwiftUI ガイド) を参照する
