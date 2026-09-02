import SwiftUI

/// API トークン画面 (Alarmify/APIToken/APITokenView.swift) のモック。
/// 発行直後の状態 (発行したトークンの表示とコピー・レシピへの導線) と発行済み一覧を、本番の構成に忠実に再現する。
/// トークンの値は見本のため verbatim
struct MockAPITokenScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ja: API トークン
            Text("API tokens")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.paper)
                .padding(.top, 72)

            VStack(alignment: .leading, spacing: 10) {
                // ja: 発行したトークン
                sectionLabel(Text("Issued token"))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "alfy_live_3b0e0c6e9f1b4c0a9e7d1f2a3b4c5d6e")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(16)
                    HairlineDivider().padding(.leading, 16)
                    // ja: トークンをコピーする
                    actionRow(Text("Copy token"), systemName: "doc.on.doc")
                    HairlineDivider().padding(.leading, 16)
                    // ja: curl の例をコピーする
                    actionRow(Text("Copy curl example"), systemName: "terminal")
                    HairlineDivider().padding(.leading, 16)
                    // ja: このトークン入りの連携レシピ
                    actionRow(Text("Integration recipes with this token"), systemName: "chevron.right", isNavigation: true)
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
                // ja: この値を見られるのは今だけです。外部サービスに設定してから閉じてください。
                Text("This value is shown only once. Save it into your service before closing.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.paper.opacity(0.5))
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                // ja: 発行済みのトークン
                sectionLabel(Text("Tokens"))
                VStack(alignment: .leading, spacing: 0) {
                    tokenRow(prefix: "alfy_live_3b0e…", createdAt: "2026/09/02 3:05")
                    HairlineDivider().padding(.leading, 16)
                    tokenRow(prefix: "alfy_live_8c41…", createdAt: "2026/08/28 21:14")
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
            }

            // ja: トークンを発行する
            Text("Issue a token")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.signal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night)
    }

    /// セクションの小見出し (大文字トラッキング)
    private func sectionLabel(_ label: Text) -> some View {
        label
            .font(.system(size: 12, weight: .semibold))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(Color.paper.opacity(0.5))
    }

    /// 操作行 (ボタン・遷移)。静的レンダリング用に Text で表現する
    private func actionRow(_ label: Text, systemName: String, isNavigation: Bool = false) -> some View {
        HStack(spacing: 10) {
            label
                .font(.system(size: 17))
                .foregroundStyle(isNavigation ? Color.paper : Color.signal)
            Spacer()
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isNavigation ? Color.paper.opacity(0.3) : Color.signal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// 発行済みトークン 1 件 (prefix と発行日時)。日時は見本のため verbatim
    private func tokenRow(prefix: String, createdAt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: prefix)
                .font(.system(size: 17, design: .monospaced))
                .foregroundStyle(Color.paper)
            Text(verbatim: createdAt)
                .font(.system(size: 13))
                .foregroundStyle(Color.paper.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
