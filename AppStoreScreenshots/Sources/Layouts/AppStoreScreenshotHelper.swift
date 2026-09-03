import SwiftUI

// MARK: - デバイスフレーム

/// モック画面を実機解像度 (393×852pt) でレンダリングし、縮小表示する。
/// フレーム内のレイアウトが縮小率に依存せず本番画面と一致するようにするための仕組み
/// (取り込み元: bannzai/mementomorning の同名 struct)
struct ScreenshotContentImage<Content: View>: View {
    /// レンダリングする論理サイズ。iPhone の実機 pt サイズを渡す
    let size: CGSize
    /// レンダリング対象のモック画面
    let content: Content

    /// @ViewBuilder でモック画面を受け取るために明示的に init を定義する
    init(size: CGSize, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    var body: some View {
        renderImage()
    }

    /// ImageRenderer で実サイズ描画した画像を返す。scale 3.0 は実機 (@3x) と同じ解像度で文字を滲ませないため
    @MainActor
    private func renderImage() -> some View {
        let renderer = ImageRenderer(
            content: content.frame(width: size.width, height: size.height)
        )
        renderer.scale = 3.0
        return Group {
            if let uiImage = renderer.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

/// デバイスフレームのベゼル表現。画像アセットは使わず、ヘアラインのストロークだけで表現する
struct IPhoneFrameOverlay: View {
    /// ストロークの色。既定値は夜背景用のヘアライン
    var strokeColor = Color.paper.opacity(0.18)

    var body: some View {
        RoundedRectangle(cornerRadius: 44)
            .stroke(strokeColor, lineWidth: 3)
    }
}

// MARK: - モック画面の共通部品

/// モック画面の pill ボタン風表示。静的レンダリング (ImageRenderer) 用に Button ではなく Text で表現する
struct MockPillLabel: View {
    /// pill 内のラベル
    let label: Text
    /// true なら primary (シグナル橙の地に夜色の文字)、false なら secondary (ヘアライン枠のみ)
    var isPrimary = true

    var body: some View {
        label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.night : Color.paper.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                if isPrimary {
                    Capsule().fill(Color.signal)
                } else {
                    Capsule().stroke(Color.paper.opacity(0.25), lineWidth: 1)
                }
            }
    }
}

/// モック画面の SF Symbol アイコン (角丸の地 + シンボル)。連携元・履歴の行頭に使う
struct MockSymbolTile: View {
    /// 表示する SF Symbol 名
    let systemName: String
    /// シンボルの色。既定はシグナル橙
    var tint = Color.signal

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.panel))
    }
}
