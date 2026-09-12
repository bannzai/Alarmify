# Signalarm デザイン成果物 (design_handoff)

Issue #60 で作成した全画面のデザイン。アプリへの反映は #6 が本ディレクトリを読んで行う。

- デザインカンバス (Claude Code の `/design`。ダーク / ライトの 2 ページ、23 アートボード):
  https://claude.ai/code/artifact/cc6eddca-ab3e-40ac-96fc-2851ea6a0adc
- 要件の正: https://github.com/bannzai/Alarmify/issues/1 のプロンプト本文 (名称は Signalarm に読み替え) と https://github.com/bannzai/Alarmify/issues/60

## 構成

| パス | 内容 |
| --- | --- |
| `tokens.md` | デザイントークン (色・タイポグラフィ・余白・角丸)。ダークは既存の `Alarmify/Shared/DesignTokens.swift` と `docs/index.html` の値、ライトは本 issue で新設 |
| `screens/*.md` | 画面ごとの仕様 (構成要素・状態・確定コピー en / ja・実装メモ) |
| `png/*.png` | アートボードの書き出し (390×844 の 2x)。ファイル名はアートボード名と同じ |
| `canvas/build.mjs` | アートボード (`*.dc.html`) と `canvas.json` の生成元。画面構成はここが正 |
| `canvas/*.dc.html`, `canvas/canvas.json` | 生成済みのアートボードとカンバスのレイアウト。カンバスを作り直す時の入力 |
| `canvas/shoot-artboards.sh` | アートボードを agent-browser で撮影して `png/` を更新する |
| `canvas/seed-canvas.sh` | アートボードからカンバスのページを組み立てて検査する (`/design` skill の同梱ツールを使う) |
| `onboarding-rationale.md` | `/onboarding-design` の分析結果と、オンボーディング設計の根拠 |
| `paywall-review.md` | `/paywall-design review` の結果と、ペイウォールの見直し提案 |

## アートボード一覧

ダークページ (入口。`Main.dc.html` がオンボーディング 1 枚目):

| アートボード | 画面 | PNG |
| --- | --- | --- |
| Main | オンボーディング 1: コンセプト | `png/Main.png` |
| OnboardingAlarmsDark | オンボーディング 2: アラームの権限 | `png/OnboardingAlarmsDark.png` |
| OnboardingPushDark | オンボーディング 3: 通知の権限 | `png/OnboardingPushDark.png` |
| OnboardingTokenDark | オンボーディング 4: 最初の API トークン | `png/OnboardingTokenDark.png` |
| OnboardingTestDark | オンボーディング 5: テストアラーム | `png/OnboardingTestDark.png` |
| HomeDark | ホーム | `png/HomeDark.png` |
| TokensDark | API トークン | `png/TokensDark.png` |
| RecipesDark | 連携レシピ (一覧) | `png/RecipesDark.png` |
| RecipeDetailDark | 連携レシピ (GitHub Actions の詳細) | `png/RecipeDetailDark.png` |
| SettingsDark | 設定 | `png/SettingsDark.png` |
| PaywallDark | ペイウォール | `png/PaywallDark.png` |
| LockScreen | ロック画面 / Dynamic Island の発火表示 (ダークのみ) | `png/LockScreen.png` |

ライトページ: 上記の `*Dark` を `*Light` に読み替える (`OnboardingConceptLight` 〜 `PaywallLight`)。ロック画面の Live Activity は常に暗い地に描かれるためライト版は無い。

## カンバスを作り直す

1. `node design_handoff/canvas/build.mjs` でアートボードと `canvas.json` を再生成する (冪等)
2. `bash design_handoff/canvas/shoot-artboards.sh` で `png/` を更新する (agent-browser。セッション名は worktree 名)
3. Claude Code で `/design` を起動して skill の base directory を得て、`DESIGN_SKILL_DIR=<base directory> bash design_handoff/canvas/seed-canvas.sh` でページを組み立てる
4. 組み立てたページを上記のカンバス URL へ再公開する (`/design` skill の「Updating an existing canvas」)

## 前提と未確定事項

- ペイウォールの価格 ($14.99 / 年、$1.99 / 月) は `documents/PROJECT.md` の目安を見本として置いた値。アプリは RevenueCat の offering から取得できた価格だけを表示し、固定値のフォールバックを持たない (`~/.claude/rules/coding-rules-no-default-for-external-source-of-truth.md`)
- 履歴の「送信元」はトークンの prefix (`alm_9f2c`) で表す。`AlarmHistoryEntry.tokenID` から prefix を引ける。画面に置いたサービス名 (GitHub Actions 等) はトークンに名前を付ける前提で、`APIToken` にラベルを持たせるバックエンドの変更が必要 (Pro の「サービスごとのトークン」で意味を持つ)。ラベル無しのトークンは prefix だけを表示する
- 「Ring a test」(ホーム) と「Ring a test alarm in 1 minute」(オンボーディング) は既存の `ContentView.scheduleTestAlarm` (1 分後のテストアラーム) をそのまま使う
- 設定の「Permissions」は AlarmKit の権限状態 (`AlarmKitScheduler.authorizationState`) と通知の権限状態 (`UNUserNotificationCenter` の設定) を表示する
