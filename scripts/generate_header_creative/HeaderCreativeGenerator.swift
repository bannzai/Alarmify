import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// App Store creative assets (product page header / search results) と LP の OGP 画像を SwiftUI で描画して
// PNG 出力するジェネレータ。macOS の swiftc でコンパイルして実行する (実行方法は同ディレクトリの
// generate_header_creative.sh)。配色は AppStoreScreenshots/Sources/DesignTokens.swift を同時にコンパイルして共有する。
//
// canvas と Art Safe Area の値は Apple 公式テンプレート PSD の実測
// (appstore-header-creative skill の fetch_template_spec.sh、2026-09-02 取得) が根拠。
// キーコンテンツ (シグナル + ベル + コピー) は Art Safe Area 内に収める。

/// 生成対象のアセット種別。canvas サイズと Art Safe Area は Apple 公式テンプレート PSD の実測値
enum CreativeAssetType: String, CaseIterable {
    case productPageHeader = "product_page_header"
    case searchResults = "search_results"

    /// テンプレート PSD の作業領域サイズ (px)
    var canvasSize: CGSize {
        switch self {
        case .productPageHeader: CGSize(width: 3840, height: 1646)
        case .searchResults: CGSize(width: 3840, height: 2560)
        }
    }

    /// キーコンテンツを収める Art Safe Area (px)。テンプレート PSD の同名レイヤーの実測座標
    var artSafeArea: CGRect {
        switch self {
        case .productPageHeader: CGRect(x: 1097, y: 493, width: 2743 - 1097, height: 1154 - 493)
        case .searchResults: CGRect(x: 836, y: 765, width: 3004 - 836, height: 1795 - 765)
        }
    }

    /// コピーの文字サイズ (px)。各言語の最長行 + グリフが Art Safe Area の幅 (header 1646px / search 2168px) に
    /// 収まるように選び、--safe-area-guide の目視で検証した値
    func copyFontSize(for language: CreativeAssetLanguage) -> CGFloat {
        switch (self, language) {
        case (.productPageHeader, .ja): 108
        case (.productPageHeader, .enUS): 110
        case (.searchResults, .ja): 140
        case (.searchResults, .enUS): 144
        }
    }
}

/// 生成する言語。App Store のローカライズ言語 (ja / en-US) に対応する
enum CreativeAssetLanguage: String, CaseIterable {
    case ja
    case enUS = "en-US"

    /// 訴求コピー。SSOT は AppStoreScreenshots/Localizable.xcstrings の "Webhooks become\nreal alarms"
    /// (スクリーンショット 1 枚目のキャッチコピー) で、header はスクリーンショットと同じ 1 つのアイデアで統一する。
    /// 折り返し位置を制御するため明示的な改行を入れて転記する
    var copyText: String {
        switch self {
        case .ja: "Webhook を\n本物のアラームに"
        case .enUS: "Webhooks become\nreal alarms"
        }
    }
}

/// アプリアイコンと同モチーフのグリフ (橙のシグナルのアーク 4 本 + 紙色のベル)。
/// 「届いた webhook がベルを鳴らす」を、文字なしで伝える視覚要素。
/// アークはベルの左上の肩を中心にした四分円で、アイコン (AppIcon.png) と同じ配置比率にする
struct SignalBellGlyph: View {
    /// グリフの一辺 (px)。正方形の領域に描く
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let radius = size * (0.16 + CGFloat(index) * 0.11)
                Circle()
                    // Circle のパスは 3 時から時計回りのため、0.5〜0.75 が左上の四分円になる
                    .trim(from: 0.5, to: 0.75)
                    .stroke(Color.signal, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: size * 0.50, y: size * 0.50)
            }
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.52, weight: .regular))
                .foregroundStyle(Color.paper)
                .position(x: size * 0.70, y: size * 0.68)
        }
        .frame(width: size, height: size)
    }
}

/// creative asset の 1 枚分のビュー。
/// 夜色の地 + 左上のシグナルの微光 (スクリーンショットと同モチーフ) + グリフ + コピーで構成し、
/// スクリーンショット基盤 (AppStoreScreenshots) と配色・タイポグラフィを揃える
struct CreativeAssetView: View {
    /// 生成対象のアセット種別
    let assetType: CreativeAssetType
    /// 生成する言語
    let language: CreativeAssetLanguage
    /// Art Safe Area を赤枠で重ねる検証用フラグ (成果物では false)
    let showsSafeAreaGuide: Bool

    var body: some View {
        let fontSize = assetType.copyFontSize(for: language)
        ZStack {
            Color.night

            signalGlow

            HStack(alignment: .center, spacing: fontSize * 0.7) {
                SignalBellGlyph(size: fontSize * 2.4)
                Text(verbatim: language.copyText)
                    // スクリーンショット (40pt heavy) と同じ極太ウェイトで統一する
                    .font(.system(size: fontSize, weight: .heavy))
                    .lineSpacing(fontSize * 0.18)
                    .foregroundStyle(Color.paper)
                    .multilineTextAlignment(.leading)
                    .fixedSize()
            }
            // キーコンテンツを Art Safe Area の中央に置く (canvas 中央と Safe Area 中央は一致する)

            if showsSafeAreaGuide {
                safeAreaGuide
            }
        }
        .frame(width: assetType.canvasSize.width, height: assetType.canvasSize.height)
    }

    /// スクリーンショットの AppStoreScreenshotSignalLayout と同じ、左上から差し込むシグナルの微光
    private var signalGlow: some View {
        RadialGradient(
            colors: [Color.signal.opacity(0.28), Color.signal.opacity(0)],
            center: .topLeading,
            startRadius: 0,
            endRadius: assetType.canvasSize.height * 0.9
        )
    }

    /// Art Safe Area の検証用赤枠
    private var safeAreaGuide: some View {
        Rectangle()
            .stroke(Color.red, lineWidth: 4)
            .frame(width: assetType.artSafeArea.width, height: assetType.artSafeArea.height)
            .position(x: assetType.artSafeArea.midX, y: assetType.artSafeArea.midY)
    }
}

/// LP (docs/index.html) の OGP 画像 (1200×630)。og:image は英語のみ (og:locale en_US)。
/// header と同じグリフ + ワードマーク + LP の見出しと同じ一言で構成する
struct OpenGraphImageView: View {
    static let canvasSize = CGSize(width: 1200, height: 630)

    var body: some View {
        ZStack {
            Color.night

            RadialGradient(
                colors: [Color.signal.opacity(0.28), Color.signal.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 560
            )

            HStack(alignment: .center, spacing: 64) {
                SignalBellGlyph(size: 300)
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: "Alarmify")
                        .font(.system(size: 96, weight: .heavy))
                        .foregroundStyle(Color.paper)
                    // LP の <title> と同じ一言 (docs/index.html)
                    Text(verbatim: "Turn any webhook into\na real iPhone alarm")
                        .font(.system(size: 36, weight: .medium))
                        .lineSpacing(6)
                        .foregroundStyle(Color.paper.opacity(0.7))
                        .fixedSize()
                }
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
    }
}

/// CGImage を不透明 (alpha なし) の PNG として書き出す。書き出しに失敗した場合は false を返す。
/// ImageRenderer の出力は alpha 付きだが、App Store creative assets は透過の可否が未公表のため
/// (appstore-header-creative skill references/asset-spec.md「未確定事項」)、拒否リスクを避けて alpha を落とす
func writePNG(cgImage: CGImage, url: URL) -> Bool {
    guard let opaqueContext = CGContext(
        data: nil,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return false
    }
    opaqueContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    guard let opaqueImage = opaqueContext.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(destination, opaqueImage, nil)
    return CGImageDestinationFinalize(destination)
}

/// SwiftUI ビューを canvas 実寸で描画して PNG に書き出す。失敗時はメッセージを出して終了する
@MainActor
func render<Content: View>(_ content: Content, to url: URL, label: String) {
    let renderer = ImageRenderer(content: content)
    // canvas 実寸 (px) をポイント単位で指定しているため、scale 1 で 1pt = 1px として出力する
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else {
        FileHandle.standardError.write(Data("error: \(label) の描画に失敗した\n".utf8))
        exit(1)
    }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard writePNG(cgImage: cgImage, url: url) else {
        FileHandle.standardError.write(Data("error: \(url.path) の書き出しに失敗した\n".utf8))
        exit(1)
    }
    print("generated: \(url.path) (\(cgImage.width)x\(cgImage.height))")
}

/// 全アセット (種別 x 言語) と OGP 画像を出力するエントリポイント。
/// 同名ファイルへの上書き出力のため再実行しても結果は変わらない (冪等)
@main
struct HeaderCreativeGenerator {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        // フラグ形の値 (--safe-area-guide 等) を出力先として誤解釈しないよう拒否する
        guard arguments.count >= 3, !arguments[1].hasPrefix("--"), !arguments[2].hasPrefix("--") else {
            FileHandle.standardError.write(Data("usage: \(arguments[0]) <creative assets の出力ディレクトリ> <og.png の出力パス> [--safe-area-guide]\n".utf8))
            exit(2)
        }
        let outputDirectoryURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let openGraphURL = URL(fileURLWithPath: arguments[2])
        let showsSafeAreaGuide = arguments.contains("--safe-area-guide")

        for assetType in CreativeAssetType.allCases {
            for language in CreativeAssetLanguage.allCases {
                render(
                    CreativeAssetView(assetType: assetType, language: language, showsSafeAreaGuide: showsSafeAreaGuide),
                    to: outputDirectoryURL.appendingPathComponent("\(assetType.rawValue)_\(language.rawValue).png"),
                    label: "\(assetType.rawValue) \(language.rawValue)"
                )
            }
        }
        render(OpenGraphImageView(), to: openGraphURL, label: "og")
    }
}
