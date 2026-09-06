import SwiftUI

// アプリ本体・Extension の配色トークン。ストア素材 (AppStoreScreenshots/Sources/DesignTokens.swift)・LP・アプリアイコンと同じ値にする。
// 受領デザイン (#6) の反映時にトークン一式をここへ揃える

extension Color {
    /// アクセント (シグナル橙)。#F97316。アイコンの「届いた webhook」のアークと同じ色で、アラームの発火 UI (Live Activity) の tint に使う
    static let signal = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
}
