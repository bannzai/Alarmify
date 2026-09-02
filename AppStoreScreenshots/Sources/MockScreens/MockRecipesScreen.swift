import SwiftUI

/// 連携レシピ画面 (Alarmify/Recipes/RecipesView.swift) のモック。
/// 本番の一覧 (連携先の名称 + 要約 + 遷移) に忠実に、6 件のレシピをそのまま並べる。
/// 名称は固有名詞のため verbatim、要約は本番と同じ英語原文をキーにしてローカライズする
struct MockRecipesScreen: View {
    /// レシピ 1 件分 (名称と要約は RecipesView の displayName / summary と同じ)
    private struct Recipe {
        let name: String
        let summary: Text
    }

    private let recipes: [Recipe] = [
        // ja: スクリプト・crontab・CI から 1 行の curl で鳴らす
        Recipe(name: "cron / shell", summary: Text("One curl line for scripts, crontab and CI jobs")),
        // ja: workflow の完了・失敗時に鳴らす
        Recipe(name: "GitHub Actions", summary: Text("Ring when a workflow finishes or fails")),
        // ja: 任意のオートメーションから呼べる rest_command
        Recipe(name: "Home Assistant", summary: Text("A rest_command you can call from any automation")),
        // ja: 「URL の内容を取得」アクションで鳴らす
        Recipe(name: "Shortcuts", summary: Text("The 'Get Contents of URL' action, for Shortcuts automations")),
        // ja: アラートの発火時に鳴らす Webhook 通知先
        Recipe(name: "Grafana", summary: Text("A webhook contact point that rings when an alert fires")),
        // ja: モニターがダウンした時に鳴らす Webhook 通知
        Recipe(name: "Uptime Kuma", summary: Text("A webhook notification that rings when a monitor goes down")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ja: 連携レシピ
            Text("Integration recipes")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.paper)
                .padding(.top, 72)

            VStack(spacing: 0) {
                ForEach(Array(recipes.enumerated()), id: \.offset) { index, recipe in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: recipe.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.paper)
                            recipe.summary
                                .font(.system(size: 13))
                                .foregroundStyle(Color.paper.opacity(0.55))
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.paper.opacity(0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    if index < recipes.count - 1 {
                        HairlineDivider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))

            HStack(spacing: 10) {
                Image(systemName: "book")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.signal)
                // ja: API リファレンス
                Text("API reference")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.paper)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night)
    }
}
