import SwiftUI

// 受領デザイン (design_handoff/) の共通部品。ボタン・カード・見出し・チップ・コードブロックを画面間で揃える。
// 色・寸法は Alarmify/Shared/DesignSystem/DesignTokens.swift のトークンだけを使う

/// 主ボタン。`signal` の塗りに `onSignal` の文字。1 画面に 1 つだけ置く。
/// `height` は主ボタン (52) と小ボタン (40。API トークン画面の「Copy token」) で使い分ける
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = DesignMetrics.primaryButtonHeight
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onSignal)
            .padding(.horizontal, DesignMetrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.signal, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4))
            .contentShape(Rectangle())
    }

    /// 小ボタンは角丸も小さくする (tokens.md「ボタンの角丸」)
    private var cornerRadius: CGFloat {
        height < DesignMetrics.secondaryButtonHeight ? DesignMetrics.smallButtonCornerRadius : DesignMetrics.buttonCornerRadius
    }
}

/// 副ボタン。`hairlineStrong` の枠に `paperSecondary` の文字
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = DesignMetrics.secondaryButtonHeight
    /// 幅いっぱいに伸ばすか。行の中に置く小さな副ボタン (「Done」) は伸ばさない
    var expands = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Color.paperSecondary)
            .padding(.horizontal, DesignMetrics.rowHorizontalPadding)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: height)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.hairlineStrong, lineWidth: DesignMetrics.hairlineWidth))
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
            .contentShape(Rectangle())
    }

    private var cornerRadius: CGFloat {
        height < DesignMetrics.secondaryButtonHeight ? DesignMetrics.smallButtonCornerRadius : DesignMetrics.buttonCornerRadius
    }
}

/// テキストボタン。`paperTertiary` の文字だけで、オンボーディングの「Not now」「Skip」に使う
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Color.paperTertiary)
            .frame(maxWidth: .infinity, minHeight: DesignMetrics.textButtonHeight)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// 橙の座布団の小ボタン。`signalSoft` の地に `signalText` の文字 (オンボーディングのトークンカードの「Copy」)
struct SoftAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.signalText)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color.signalSoft, in: RoundedRectangle(cornerRadius: DesignMetrics.smallButtonCornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// 橙のテキストだけのリンク風ボタン (セクション見出しの「Ring a test」、コードブロックの「Copy」)
struct AccentTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.signalText)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// カード。`panel` の地に `border` の枠。強調カードは枠を `signalLine` にする
    func card(border: Color = .hairline, cornerRadius: CGFloat = DesignMetrics.cardCornerRadius) -> some View {
        background(Color.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(border, lineWidth: DesignMetrics.hairlineWidth))
    }

    /// 画面の地。NavigationStack の中身に付ける
    func screenBackground() -> some View {
        background(Color.night.ignoresSafeArea())
    }

    /// 行の内側の余白。カードの中の 1 行に付ける。
    /// 行全体をタップ領域にする (`.buttonStyle(.plain)` の NavigationLink は Spacer の部分がタップに反応しないため)
    func rowPadding() -> some View {
        padding(.horizontal, DesignMetrics.rowHorizontalPadding)
            .padding(.vertical, DesignMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: DesignMetrics.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// 折り返す横並び。チップの列のように、幅に収まらない要素を次の行へ送る。行の中では上下中央に揃える
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + spacing
            }
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

extension Text {
    /// eyebrow (等幅の小さな大文字。tokens.md「Eyebrow」)。letter-spacing 0.2em を 11pt に換算した 2.2pt を空ける
    func eyebrowStyle(color: Color = .signalText) -> some View {
        font(.caption2.monospaced())
            .textCase(.uppercase)
            .tracking(2.2)
            .foregroundStyle(color)
    }

    /// セクション見出し (13 semibold の大文字。tokens.md「Section header」)。letter-spacing 0.04em を 13pt に換算した 0.5pt を空ける。
    /// ファイル名・設定項目名のように大文字小文字が意味を持つ見出しは `uppercase: false` にする
    func sectionHeaderStyle(uppercase: Bool = true) -> some View {
        font(.footnote.weight(.semibold))
            .textCase(uppercase ? .uppercase : nil)
            .tracking(0.5)
            .foregroundStyle(Color.paperTertiary)
    }
}

/// セクション見出しの行。右端に操作 (「Ring a test」等) を置ける。
/// `dense` は設定のように行が詰まった画面で上下の余白を縮める (tokens.md「セクション見出しの上下」)
struct SectionHeader<Trailing: View>: View {
    let title: Text
    var dense = false
    var uppercase = true
    @ViewBuilder var trailing: Trailing

    init(_ title: Text, dense: Bool = false, uppercase: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.dense = dense
        self.uppercase = uppercase
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title.sectionHeaderStyle(uppercase: uppercase)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
        .padding(.top, dense ? 14 : 20)
        .padding(.bottom, dense ? 6 : 8)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: Text, dense: Bool = false, uppercase: Bool = true) {
        self.init(title, dense: dense, uppercase: uppercase) { EmptyView() }
    }
}

/// ヘアラインの区切り線 1 本。カードの中の行の区切りに使う
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: DesignMetrics.hairlineWidth)
    }
}

/// 行の右端のシェブロン (遷移する行の目印)
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.paperQuaternary)
    }
}

/// 等幅の小さなチップ。トークンの prefix・ペイウォールの「Best value」に使う。
/// `filled` は `signalSoft` の地 (強調)、そうでなければ `hairlineStrong` の枠だけ (レシピの名前)
struct Chip: View {
    let text: Text
    var filled = true

    var body: some View {
        text
            .font(.caption2.monospaced())
            .tracking(0.2)
            .lineLimit(1)
            .foregroundStyle(filled ? Color.signalText : Color.paperSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: DesignMetrics.chipHeight)
            .background(filled ? Color.signalSoft : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.signalLine : Color.hairlineStrong, lineWidth: DesignMetrics.hairlineWidth))
    }
}

/// コードブロック。`nightInset` の地に等幅のコードと、下段に「Copy」の行。
/// `wraps` が false のコード (YAML はインデントが意味を持つ) は折り返さず横スクロールにする。
/// `copyText` はコピーする瞬間に文字列を作り直す (curl の `fire_at` のように描画時の値が古くなるコードのため)。nil なら表示中の `code` をコピーする
struct CodeBlock: View {
    let code: String
    var wraps = true
    /// 「Copy」ボタンの accessibilityIdentifier (mobile-mcp / Maestro からの検出用)
    var copyIdentifier: String
    var copyText: (() -> String)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if wraps {
                    codeText
                } else {
                    ScrollView(.horizontal) {
                        codeText
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            HairlineDivider()
            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = copyText?() ?? code
                } label: {
                    // ja: コピー
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(AccentTextButtonStyle())
                .accessibilityIdentifier(copyIdentifier)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: DesignMetrics.smallButtonHeight)
        }
        .background(Color.nightInset, in: RoundedRectangle(cornerRadius: DesignMetrics.codeBlockCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.codeBlockCornerRadius, style: .continuous).strokeBorder(Color.hairline, lineWidth: DesignMetrics.hairlineWidth))
    }

    private var codeText: some View {
        Text(verbatim: code)
            .font(.caption.monospaced())
            .foregroundStyle(Color.paperSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// オンボーディングの進捗 (5 分割のバー。tokens.md「オンボーディングのプログレス」)
struct ProgressSegments: View {
    let total: Int
    /// 塗る本数 (先頭から)
    let filled: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Color.signal : Color.hairlineStrong)
                    .frame(height: 3)
            }
        }
    }
}
