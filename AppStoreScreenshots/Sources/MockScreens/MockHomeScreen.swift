import SwiftUI

/// アプリのホーム (次のアラーム + 履歴) のモック。
/// 「取り消しも変更もサーバーから」を、API 経由の変更・取り消しが履歴として残る様子で伝える
struct MockHomeScreen: View {
    /// 履歴 1 件分。発火・変更・取り消しをアイコンと色で区別する
    private struct HistoryEntry {
        let systemName: String
        let tint: Color
        let title: Text
        let detail: Text
    }

    private let history: [HistoryEntry] = [
        // ja: デプロイ完了
        // ja: 3:07 に発火
        HistoryEntry(systemName: "bell.fill", tint: .signal, title: Text("Deploy finished"), detail: Text("Fired at 3:07")),
        // ja: サーバーダウン
        // ja: 7:30 に変更
        HistoryEntry(systemName: "clock.arrow.circlepath", tint: Color.paper.opacity(0.7), title: Text("Server down"), detail: Text("Rescheduled to 7:30")),
        // ja: バックアップ完了
        // ja: API から取り消し
        HistoryEntry(systemName: "xmark.circle", tint: Color.paper.opacity(0.45), title: Text("Backup finished"), detail: Text("Cancelled by API")),
        // ja: 玄関のドアが開いた
        // ja: 1:12 に発火
        HistoryEntry(systemName: "bell.fill", tint: .signal, title: Text("Front door opened"), detail: Text("Fired at 1:12")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(verbatim: "Alarmify")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.paper)
                .padding(.top, 72)

            VStack(alignment: .leading, spacing: 10) {
                // ja: 次のアラーム
                Text("Next alarm")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.paper.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "7:30")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(Color.paper)
                    // ja: 今日
                    Text("Today")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.paper.opacity(0.55))
                }
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.signal)
                    // ja: サーバーダウン
                    Text("Server down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.paper)
                    Text(verbatim: "· Grafana")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.paper.opacity(0.5))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))

            VStack(alignment: .leading, spacing: 10) {
                // ja: 履歴
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.paper.opacity(0.5))
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 14) {
                            MockSymbolTile(systemName: entry.systemName, tint: entry.tint)
                            VStack(alignment: .leading, spacing: 5) {
                                entry.title
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.paper)
                                entry.detail
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.paper.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        if index < history.count - 1 {
                            HairlineDivider()
                        }
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
