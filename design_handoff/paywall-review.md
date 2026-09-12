# ペイウォールの見直し (/paywall-design review の結果)

`/paywall-design review` (`~/.claude/skills/paywall-design/SKILL.md`) を現在の `Alarmify/Features/Purchase/PaywallPage.swift` に対して実行した記録。Phase 1 のヒアリングは無人実行のため Issue と `documents/PROJECT.md` から埋めた。

## アプリ情報

| 項目 | 値 |
| --- | --- |
| カテゴリ | 開発者向けツール / ユーティリティ |
| 収益化 | フリーミアム + サブスクリプション (年額主・月額副。PROJECT.md の課金設計) |
| ターゲット | エンジニア・ホームオートメーション利用者。課金意欲は「使い込んで上限に当たった時」に高い |
| 現在のペイウォール | 仮 UI (`List` に導入文・プランのボタン・復元・法務リンク)。年額を先に並べる構造は実装済み |
| プラン | Pro 年額 $14.99 目安 / 月額 $1.99〜2.99 目安 (価格は RevenueCat の offering が正) |
| 表示の契機 | 設定 (`.settings`)、無料枠の上限 (`.freeQuotaExceeded`: API トークン発行の `plan_limit_exceeded`)、ホームの履歴 (`.alarmHistory`) |

## 1. 到達率の確認 (到達率ファースト)

**到達率は計測できていない。** PROJECT.md の方針で Analytics / Crashlytics は MVP に入れておらず、ペイウォール表示・閉じる・購入のイベントが無い。SKILL.md の review モードに従い、ペイウォール自体の改善より先に計測の整備を提案する:

- 最低セット (`~/.claude/skills/onboarding-design/references/monetization-onboarding.md`「計測イベントの最低セット」): 初回起動 / オンボーディング開始 / 各ステップ表示 / 完了 / ペイウォール表示 (trigger 付き) / ペイウォール閉じる / トライアル開始 / 購入完了
- 到達率の定義: 同一インストールコホートのユニークユーザーのうち、一定期間内に一度以上ペイウォールを表示した人の割合
- 導入の判断 (Analytics を入れるか・何を使うか) はユーザーの決定事項。本 issue では扱わない

計測が無い間の構造的な見立て: 現在のペイウォールは設定の奥 (Settings > Upgrade to Pro) と、上限に当たった時の 2 経路で、無料枠の 20 回 / 月に当たらないユーザーには一度も表示されない。ホームの `See more history with Pro` はあるが、履歴が 3 件以下のうちは意味を持たない。到達率は低い側と推定する。

## 2. 現状の評価 (UI 設計チェックリスト)

| 項目 | 現状 | 判定 |
| --- | --- | --- |
| CTA は 1 画面に 1 つ | 年額・月額の 2 ボタンが同格 | × |
| 閉じるボタン | ナビの Close | ○ |
| 価格が明確 | `$X / year`・`$X / month` のみ。月額換算や差が無い | △ |
| トライアル条件 | トライアル無し (商品設定次第) | 対象外 |
| 解約方法への導線 | 自動更新・解約の記載が無い | × |
| タッチターゲット 44pt 以上 | List の行 | ○ |
| コントラスト | システム標準 | ○ |
| ローディング | `ProgressView` と再読み込み導線 | ○ |
| 決済エラー時のメッセージ | alert で表示 | ○ |
| 復元ボタン | あり | ○ |

コンバージョン最適化の原則との照合:

- 透明性のある価格表示: 年額の月額換算 (`$1.25 a month billed yearly`) と自動更新の注記が無い → 追加する
- 推奨プランのハイライト: 年額を先に置くだけで視覚的な差が無い → 選択状態のカードと「Best value」のチップ
- ベネフィット訴求: 導入文が 1 文で機能を列挙している → 4 項目に分けてアイコン付きで示す (トークン / 無制限 / 履歴 / 複数端末)
- 有料プランを隠さない: オンボーディングにペイウォールを置かない方針 (Issue #60) は保ちつつ、ホームの履歴末尾に「Older alarms are kept in Pro」の行を常設し、設定には「Signalarm Pro」の行を最上段に置く。ソフトペイウォールなので閉じられる

## 3. 提案 (優先順)

1. **主ボタンを 1 つにする**: プランはカードで選択し (年額が既定で選択)、CTA は `Continue with Yearly` の 1 つ。月額はカードを選ぶと CTA の文言が `Continue with Monthly` に変わる → カンバスの `PaywallDark` / `PaywallLight`
2. **年額主・月額副を視覚化する**: 年額カードは `accentLine` の枠 + 塗りのラジオ + `Best value` チップ。月額カードは `hair2` の枠。注記は年額に「$1.25 a month billed yearly」、月額に「Cancel anytime」
3. **静かな訴求**: 見出しは `More services and every alarm kept`、リードは無料枠の内容と「Pro removes both limits」の 2 文だけ。カウントダウン・割引バッジ・紙吹雪・ソーシャルプルーフは置かない (Issue #1 のトーン)
4. **法務の注記を足す**: `Renews automatically until canceled in Settings. Prices shown in your local currency.` を CTA の直下に 11px で置き、Restore / Terms / Privacy / Legal notice を 1 行に並べる (App Store Review Guideline 3.1.2 の自動更新の明示)
5. **trigger ごとの導入文は維持する**: `PaywallTrigger` の 3 種でリードの 1 文目を変える。カンバスは `.settings` の文面。`.freeQuotaExceeded` は `You've reached the limit of the free plan`、`.alarmHistory` は `The free plan shows the 3 most recent alarms` を 1 文目にする (既存文言)
6. **価格の扱い**: 価格・期間・月額換算は RevenueCat の offering から取得できた package だけで組み立て、取得できない間はプランカードを出さず「Prices couldn't be loaded」と `Reload prices` を出す (既存の挙動を維持。`~/.claude/rules/coding-rules-no-default-for-external-source-of-truth.md`)。カンバスの `$14.99` / `$1.99` は PROJECT.md の目安を見本として置いた値
7. (計測の整備後) A/B の対象: 見出しの文言、年額の注記 (月額換算 vs 年間の差額)、ホームの Pro 行の文言。指標はペイウォール到達率と表示 → 購入の転換率

## 参考 UI の収集

`/paywall-design collect` (paywallscreens.com 等の巡回) は行っていない。理由はオンボーディングと同じで、完了条件に含まれず、トーンが Issue #1 で確定しているため。必要なら別途実行する。

## 確定コピー

短い文言は `~/.claude/rules/coding-rules-user-facing-short-copy-punctuation.md` に照合済み。

| 要素 | en | ja |
| --- | --- | --- |
| eyebrow | Signalarm Pro | Signalarm Pro |
| 見出し | More services and every alarm kept | もっと多くのサービスと すべてのアラームの記録を |
| リード (settings) | The free plan includes one token and 20 alarms a month. Pro removes both limits. | 無料プランではトークン 1 つ・月 20 回までアラームを登録できます。Pro ではどちらの上限もなくなります。 |
| 特典 | A token for every service / Unlimited alarms / Full alarm history / Rings on all your iPhones | サービスごとのトークン / 無制限のアラーム / すべてのアラーム履歴 / すべての iPhone で鳴る |
| プラン | Yearly / Best value / $1.25 a month billed yearly / Monthly / Cancel anytime / per year / per month | 年額 / おすすめ / 月あたり $1.25 (年払い) / 月額 / いつでも解約できます / 年 / 月 |
| CTA | Continue with Yearly | 年額で続ける |
| 注記 | Renews automatically until canceled in Settings. Prices shown in your local currency. | 設定で解約するまで自動更新されます。価格はお住まいの地域の通貨で表示されます。 |
| リンク | Restore / Terms / Privacy / Legal notice | 購入を復元 / 利用規約 / プライバシー / 特定商取引法に基づく表記 |
