import SwiftUI
import UIKit

// アプリ本体・Extension の配色・タイポグラフィ・寸法のトークン。値は design_handoff/tokens.md が正で、
// ダークはストア素材 (AppStoreScreenshots/Sources/DesignTokens.swift)・LP (docs/index.html)・アプリアイコンと同じ値。
// ライトは UITraitCollection の dynamic provider で分ける (Asset Catalog を持たない Extension でも同じ定義を使えるようにするため)

extension UIColor {
    /// `0xRRGGBB` の 24 bit 値から作る。tokens.md の 16 進表記をそのまま書けるようにする
    fileprivate convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// ダーク / ライトで値を切り替える色。外観の判定は描画時の trait に任せる
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    /// 画面の地 (tokens.md `bg`)。ダーク #0A0A0B / ライト #F5F5F3
    static let night = dynamic(dark: UIColor(rgb: 0x0A0A0B), light: UIColor(rgb: 0xF5F5F3))
    /// コードブロック・インセットの地 (`bg2`)。ダーク #0F1012 / ライト #ECECE9
    static let nightInset = dynamic(dark: UIColor(rgb: 0x0F1012), light: UIColor(rgb: 0xECECE9))
    /// カード・行の地 (`panel`)。ダーク #15161A / ライト #FFFFFF
    static let panel = dynamic(dark: UIColor(rgb: 0x15161A), light: UIColor(rgb: 0xFFFFFF))
    /// 一次テキスト (`fg`)。ダーク #F2F2F0 / ライト #111113
    static let paper = dynamic(dark: UIColor(rgb: 0xF2F2F0), light: UIColor(rgb: 0x111113))
    /// 二次テキスト。リード文・本文 (`fg2`)
    static let paperSecondary = dynamic(dark: UIColor(rgb: 0xF2F2F0, alpha: 0.76), light: UIColor(rgb: 0x111113, alpha: 0.72))
    /// 三次テキスト。補足・セクション見出し・状態 (`fg3`)
    static let paperTertiary = dynamic(dark: UIColor(rgb: 0xF2F2F0, alpha: 0.56), light: UIColor(rgb: 0x111113, alpha: 0.52))
    /// 微弱なテキスト。法務の注記・シェブロン (`fg4`)
    static let paperQuaternary = dynamic(dark: UIColor(rgb: 0xF2F2F0, alpha: 0.35), light: UIColor(rgb: 0x111113, alpha: 0.36))
    /// 区切り線・カードの枠 (`hair`)
    static let hairline = dynamic(dark: UIColor(rgb: 0xF2F2F0, alpha: 0.10), light: UIColor(rgb: 0x111113, alpha: 0.10))
    /// 副ボタンの枠・未選択のプランの枠 (`hair2`)
    static let hairlineStrong = dynamic(dark: UIColor(rgb: 0xF2F2F0, alpha: 0.16), light: UIColor(rgb: 0x111113, alpha: 0.16))
    /// アクセント (シグナル橙、`accent`)。#F97316。主ボタンの塗り・大きな数字・アイコン・プログレスと、アラームの発火 UI (Live Activity) の tint。
    /// ダーク / ライトで変えない (Live Activity は常に暗い地に描かれる)
    static let signal = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
    /// 小さな橙のテキスト。eyebrow・リンク・ナビの戻る (`accentText`)。
    /// ライトは #C2410C に落とす (#F97316 は白地に対するコントラスト比が約 2.9:1 で 13px 前後の文字では読みにくい)
    static let signalText = dynamic(dark: UIColor(rgb: 0xF97316), light: UIColor(rgb: 0xC2410C))
    /// 橙のチップ・アイコンの座布団 (`accentSoft`)
    static let signalSoft = dynamic(dark: UIColor(rgb: 0xF97316, alpha: 0.14), light: UIColor(rgb: 0xF97316, alpha: 0.12))
    /// 強調カードの枠。次のアラーム・新しいトークン・選択中のプラン (`accentLine`)
    static let signalLine = dynamic(dark: UIColor(rgb: 0xF97316, alpha: 0.40), light: UIColor(rgb: 0xF97316, alpha: 0.45))
    /// 橙の上のテキスト (`onAccent`)。ダーク #0A0A0B / ライト #FFFFFF
    static let onSignal = dynamic(dark: UIColor(rgb: 0x0A0A0B), light: UIColor(rgb: 0xFFFFFF))
    /// アカウント削除 (`destructive`)。iOS の systemRed と同じ値
    static let destructive = dynamic(dark: UIColor(rgb: 0xFF453A), light: UIColor(rgb: 0xFF3B30))
}

extension Font {
    /// 時刻の数字 (tokens.md「時刻の数字 (等幅)」)。56pt medium の等幅。呼び出し側で `.monospacedDigit()` も付ける
    static let clockDigits = Font.system(size: 56, weight: .medium, design: .monospaced)
}

/// 余白・角丸・高さ (tokens.md「余白・角丸・寸法」)。値の根拠は同ファイルの表
enum DesignMetrics {
    /// 画面の左右余白 (カード)
    static let screenHorizontalPadding: CGFloat = 16
    /// 見出し・本文の左右余白
    static let textHorizontalPadding: CGFloat = 20
    /// オンボーディング・ペイウォールの見出しブロックの左右余白
    static let heroHorizontalPadding: CGFloat = 24
    /// カードの角丸
    static let cardCornerRadius: CGFloat = 14
    /// 権限カード・テストアラームのカードの角丸
    static let featureCardCornerRadius: CGFloat = 16
    /// ボタンの角丸 (主・副・テキスト)
    static let buttonCornerRadius: CGFloat = 12
    /// 小ボタン (40 高) の角丸
    static let smallButtonCornerRadius: CGFloat = 10
    /// コードブロックの角丸
    static let codeBlockCornerRadius: CGFloat = 10
    /// 主ボタンの高さ
    static let primaryButtonHeight: CGFloat = 52
    /// 副ボタンの高さ
    static let secondaryButtonHeight: CGFloat = 48
    /// テキストボタンの高さ (タップ領域の最小 44 と同じ)
    static let textButtonHeight: CGFloat = 44
    /// 小ボタンの高さ
    static let smallButtonHeight: CGFloat = 40
    /// チップの高さ
    static let chipHeight: CGFloat = 26
    /// 行の最小の高さ
    static let rowMinHeight: CGFloat = 48
    /// 行の内側の余白 (上下)
    static let rowVerticalPadding: CGFloat = 13
    /// 行の内側の余白 (左右)
    static let rowHorizontalPadding: CGFloat = 16
    /// ヘアラインの太さ
    static let hairlineWidth: CGFloat = 1
}
