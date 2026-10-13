import SwiftUI

/// 訴求軸 signal (1〜5 枚目)。夜色の地に左揃えの極太見出し、上部にアイコンと同じ橙のシグナルの微光を敷き、
/// 下部にデバイスフレーム付きのモック画面を置く。訴求は「外部サービスからアラームを予約」「サイレント / 集中モードでも鳴る」
/// 「何とでもつながる」(issue #10) を軸に、API 1 回での登録と、手元で管理できる API トークンで締める。
/// 見せる画面は実装済みの機能に限る (連携レシピ・API トークンは本番画面の構成をなぞる)
/// スクリーンショット番号とバリアントの対応は scripts/generate_screenshots/appstore_screenshot_env.sh の get_variant_name が正

/// 訴求軸 signal のレイアウトコンテナ。
/// 表示領域の形で 3 通りに組む: iPhone の縦長はキャッチコピーの下にデバイスフレーム、
/// 背の低い縦長 (iPhone Duo の外側ディスプレイ 466×678pt) は同じ構成でデバイスフレームを下に大きくはみ出させ、
/// 横長 (iPhone Duo の内側ディスプレイ 951×669pt) はキャッチコピーを左、デバイスフレームを右に並べる
/// (appstore-screenshot-builder skill の references/iphone-duo.md「決めること」)
struct AppStoreScreenshotSignalLayout<Content: View>: View {
    /// メインのキャッチコピー
    let title: Text
    /// サブコピー (二次テキスト 70% 紙色)
    let subtitle: LocalizedStringResource
    /// デバイスフレーム内に表示するモック画面
    @ViewBuilder let content: () -> Content

    /// キャッチコピー領域の高さ。見出し 2 行 + サブコピー 2 行分で固定し、
    /// 行数の差でデバイスフレームの位置と大きさがページごとに変わらないようにする
    private let headerHeight: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.night

                // 左上から差し込むシグナルの微光 (アイコンの橙アークと同モチーフ)。コピーの可読性を優先して淡く敷く
                RadialGradient(
                    colors: [Color.signal.opacity(0.28), Color.signal.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 520
                )

                if geometry.size.width > geometry.size.height {
                    // 横長: 左の列にキャッチコピーを縦中央で置き、右半分にデバイスフレームを上から置いて下端を切る。
                    // 内側ディスプレイは高さ 669pt で、上の余白 64 を除いた残りにモック画面の 8 割が収まる高さにする
                    // (縦長の iPhone と同じく下部ボタンまでは見せない)
                    HStack(spacing: 0) {
                        header
                            .padding(.leading, 64)
                            .padding(.trailing, 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                        fixedHeightDevice(height: (geometry.size.height - 64) / 0.8)
                            .padding(.top, 64)
                            .frame(width: geometry.size.width / 2, maxHeight: .infinity, alignment: .top)
                    }
                } else if geometry.size.height / geometry.size.width < 1.8 {
                    // 背の低い縦長 (外側ディスプレイ 466×678pt。縦横比 1.46。iPhone は 2.16 以上):
                    // 縦長の iPhone と同じ aspectRatio(.fit) ではデバイスフレームが残りの高さに合わせて幅 200pt まで縮むため、
                    // キャッチコピーの下の残りの高さにモック画面の 7 割が収まる大きさにし、下端を画面外に切る
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 56)
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)

                        fixedHeightDevice(height: (geometry.size.height - headerHeight) / 0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 56)
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)

                        Spacer()

                        // デバイスは傾けず正面・垂直に配置する (appstore-screenshot-builder skill の共通デザイン原則)。
                        // 下端はフレームごと画面外に切り、モック画面の下部ボタン省略と整合させる
                        ScreenshotContentImage(size: CGSize(width: 393, height: 852)) {
                            content()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 44))
                        .overlay(IPhoneFrameOverlay())
                        .aspectRatio(9.0 / 19.5, contentMode: .fit)
                        .padding(.horizontal, 44)
                        .offset(y: 56)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// 見出しとサブコピー
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
                // 40pt + 横 padding 28 で、6.5 インチでも日本語 8 文字 / 英字 17 文字が 1 行に収まる。
                // 改行位置は端末幅に依存させず、コピー側 (英語原文と xcstrings の ja) の \n で 2 行に固定する
                .font(.system(size: 40, weight: .heavy))
                .lineSpacing(6)
                .foregroundStyle(Color.paper)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(6)
                .foregroundStyle(Color.paper.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
    }

    /// 高さを指定したデバイスフレーム (幅は iPhone の画面比 9:19.5 から決める)。
    /// 表示領域に収めず、置いた側で下端を画面外に切るために使う
    private func fixedHeightDevice(height: CGFloat) -> some View {
        ScreenshotContentImage(size: CGSize(width: 393, height: 852)) {
            content()
        }
        .frame(width: height * 9.0 / 19.5, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 44))
        .overlay(IPhoneFrameOverlay())
    }
}

/// App Store スクリーンショット 1 枚目 - signal - 外部サービスからアラームを予約 (コアコンセプト)
struct AppStoreScreenshot1Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            title: Text("Schedule alarms\nfrom your server"),
            subtitle: "Send a time via HTTP and your iPhone alarm rings on schedule"
        ) {
            MockAlarmRingingScreen(
                // 送信元が付けたタイトルは翻訳されずそのまま届くため verbatim
                title: Text(verbatim: "Deploy finished"),
                source: Text(verbatim: "production · GitHub Actions")
            )
        }
    }
}

/// AppStoreScreenshot1Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot1Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot1Page().environment(\.colorScheme, .dark)
    }
}

/// App Store スクリーンショット 2 枚目 - signal - サイレント / 集中モードでも鳴る
struct AppStoreScreenshot2Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: サイレントも
            //
            // 集中モードも突破
            title: Text("Rings through\nSilent and Focus"),
            // ja: 通知ではなく
            //
            // 見逃せない本物のアラーム
            subtitle: "Not a notification but a real alarm you cannot miss"
        ) {
            MockAlarmRingingScreen(
                // 送信元が付けたタイトルは翻訳されずそのまま届くため verbatim
                title: Text(verbatim: "Server down"),
                source: Text(verbatim: "api-prod · Grafana"),
                showsFocusBadges: true
            )
        }
    }
}

/// AppStoreScreenshot2Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot2Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot2Page().environment(\.colorScheme, .dark)
    }
}

/// App Store スクリーンショット 3 枚目 - signal - 何とでもつながる
struct AppStoreScreenshot3Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: 何とでも
            //
            // つながる
            title: Text("Connects\nwith anything"),
            // ja: GitHub Actions や Home Assistant の
            //
            // レシピをコピーするだけ
            subtitle: "Ready-made recipes for GitHub Actions, Home Assistant, Grafana and more"
        ) {
            MockRecipesScreen()
        }
    }
}

/// AppStoreScreenshot3Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot3Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot3Page().environment(\.colorScheme, .dark)
    }
}

/// App Store スクリーンショット 4 枚目 - signal - POST ひとつで登録完了
struct AppStoreScreenshot4Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: POST ひとつで
            //
            // 登録完了
            title: Text("One POST is all\nit takes"),
            // ja: 時刻とタイトルを送るだけで
            //
            // あとは Signalarm が届ける
            subtitle: "Send a time and a title and Signalarm does the rest"
        ) {
            MockAPIRequestScreen()
        }
    }
}

/// AppStoreScreenshot4Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot4Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot4Page().environment(\.colorScheme, .dark)
    }
}

/// App Store スクリーンショット 5 枚目 - signal - トークンは手元で管理
struct AppStoreScreenshot5Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: トークンは
            //
            // 手元で管理
            title: Text("Tokens you\ncontrol"),
            // ja: アプリで発行して
            //
            // いつでも失効できる
            subtitle: "Issue it in the app and revoke it whenever you like"
        ) {
            MockAPITokenScreen()
        }
    }
}

/// AppStoreScreenshot5Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot5Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot5Page().environment(\.colorScheme, .dark)
    }
}
