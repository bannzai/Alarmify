import SwiftUI

// ストア素材 (App Store スクリーンショット・ヘッダークリエイティブ) の配色トークン。
// LP (docs/index.html の CSS 変数 --bg / --fg / --accent) とアプリアイコン
// (Alarmify/Assets.xcassets/AppIcon.appiconset: 夜色の地に橙のシグナル) の配色に揃える。
// アプリ本体にはまだデザインシステムが無いため、本体側にデザイントークンを導入する時はこのファイルの値を起点にする

extension Color {
    /// 背景 (夜)。#0A0A0B
    static let night = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0B / 255)
    /// カード・行の地。#15161A
    static let panel = Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x1A / 255)
    /// 前景 (紙)。#F2F2F0。二次テキストは opacity 0.7 / 三次 0.5 / 微弱 0.35 で使う
    static let paper = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF0 / 255)
    /// アクセント (シグナル橙)。#F97316。アイコンの「届いた webhook」のアークと同じ色で、鳴っているアラームにだけ使う
    static let signal = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
    /// ヘアライン (区切り線・フレーム)。rgba(242,242,240,0.10)
    static let hairline = Color.paper.opacity(0.10)
}

/// ヘアラインの区切り線 1 本。List を使わないモック画面での行区切りに使う
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }
}
