import SwiftUI

/// 連携元 (アラームを送ってくる外部サービス) の一覧のモック。
/// 「何とでもつながる」を、開発者が日常的に使うサービス名と直近の発火で伝える
struct MockIntegrationsScreen: View {
    /// 連携元 1 件分。サービス名はブランド名のため verbatim、直近のイベントはローカライズする
    private struct Source {
        let systemName: String
        let name: String
        let lastEvent: Text
        let time: String
    }

    private let sources: [Source] = [
        // ja: デプロイ完了
        Source(systemName: "arrow.triangle.branch", name: "GitHub Actions", lastEvent: Text("Deploy finished"), time: "3:07"),
        // ja: 玄関のドアが開いた
        Source(systemName: "house.fill", name: "Home Assistant", lastEvent: Text("Front door opened"), time: "1:12"),
        // ja: CPU 使用率 90% 超
        Source(systemName: "chart.line.uptrend.xyaxis", name: "Grafana", lastEvent: Text("CPU over 90%"), time: "23:48"),
        // ja: 朝会
        Source(systemName: "clock.arrow.circlepath", name: "cron", lastEvent: Text("Daily standup"), time: "9:00"),
        // ja: 新規注文
        Source(systemName: "bolt.horizontal.fill", name: "Zapier", lastEvent: Text("New order"), time: "18:20"),
        // ja: テストアラーム
        Source(systemName: "terminal.fill", name: "curl", lastEvent: Text("Test alarm"), time: "12:30"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                // ja: 連携元
                Text("Sources")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.paper)
                // ja: 6 件を連携中
                Text("6 connected")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.paper.opacity(0.5))
            }
            .padding(.top, 72)

            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 14) {
                        MockSymbolTile(systemName: source.systemName)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: source.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.paper)
                            source.lastEvent
                                .font(.system(size: 14))
                                .foregroundStyle(Color.paper.opacity(0.55))
                        }
                        Spacer()
                        Text(verbatim: source.time)
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(Color.paper.opacity(0.4))
                    }
                    .padding(.vertical, 14)
                    if index < sources.count - 1 {
                        HairlineDivider()
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night)
    }
}
