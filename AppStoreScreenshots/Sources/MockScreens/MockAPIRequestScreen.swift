import SwiftUI

/// アラーム登録 API (POST /v1/alarms) のリクエストとレスポンスのモック。
/// 「POST ひとつで登録完了」を、curl 1 コマンドとその応答で伝える。
/// コードはローカライズ対象外のため verbatim で書く。API のホスト名は未確定のため環境変数の形で示す。
/// リクエストとレスポンスの形は docs/api.md (firebase/functions/src/api/externalApi.ts) の契約に合わせる:
/// リクエストは JSON の Content-Type が必須、レスポンスの id は UUID、fire_at は UTC (Z) で返る
struct MockAPIRequestScreen: View {
    /// リクエストの 1 行分。強調 (フラグ・値) はシグナル橙で塗る
    private struct CodeLine {
        let text: String
        var isEmphasized = false
        var indent = 0
    }

    private let requestLines: [CodeLine] = [
        CodeLine(text: "curl -X POST $ALARMIFY_API/v1/alarms \\"),
        CodeLine(text: "-H \"Authorization: Bearer $TOKEN\" \\", indent: 1),
        CodeLine(text: "-H \"Content-Type: application/json\" \\", indent: 1),
        CodeLine(text: "-d '{", indent: 1),
        CodeLine(text: "\"fire_at\": \"2026-09-02T03:07:00+09:00\",", isEmphasized: true, indent: 2),
        CodeLine(text: "\"title\": \"Deploy finished\"", isEmphasized: true, indent: 2),
        CodeLine(text: "}'", indent: 1),
    ]

    private let responseLines: [CodeLine] = [
        CodeLine(text: "{"),
        CodeLine(text: "\"id\": \"3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e\",", indent: 1),
        CodeLine(text: "\"status\": \"scheduled\",", isEmphasized: true, indent: 1),
        CodeLine(text: "\"fire_at\": \"2026-09-01T18:07:00.000Z\",", indent: 1),
        CodeLine(text: "\"title\": \"Deploy finished\"", indent: 1),
        CodeLine(text: "}"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ja: リクエスト
            sectionLabel(Text("Request"))
                .padding(.top, 72)
            codeCard(lines: requestLines, prompt: "$")

            // ja: レスポンス
            sectionLabel(Text("Response"))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.signal)
                    Text(verbatim: "201 Created")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.paper)
                }
                codeBlock(lines: responseLines)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))

            HStack(spacing: 14) {
                MockSymbolTile(systemName: "bell.fill")
                VStack(alignment: .leading, spacing: 5) {
                    // 送信元が付けたタイトルは翻訳されずそのまま届くため、上のリクエスト・レスポンスと同じ値を verbatim で出す
                    Text(verbatim: "Deploy finished")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.paper)
                    // ja: 今日 3:07 に登録済み
                    Text("Scheduled for today at 3:07")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.paper.opacity(0.55))
                }
                Spacer()
            }
            .padding(.top, 4)

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

    /// ターミナル風のコードカード (プロンプト付き)
    private func codeCard(lines: [CodeLine], prompt: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: prompt)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.paper.opacity(0.4))
            codeBlock(lines: lines)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
    }

    /// 等幅・行単位のコード表示。インデントは 2 文字幅ずつ
    private func codeBlock(lines: [CodeLine]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: String(repeating: "  ", count: line.indent) + line.text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(line.isEmphasized ? Color.signal : Color.paper.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
