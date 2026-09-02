import SwiftUI

/// 訴求軸 signal (1〜5 枚目)。夜色の地に左揃えの極太見出し、上部にアイコンと同じ橙のシグナルの微光を敷き、
/// 下部にデバイスフレーム付きのモック画面を置く。訴求は「Webhook → 本物のアラーム」「サイレント / 集中モードでも鳴る」
/// 「何とでもつながる」(issue #10) を軸に、API 1 回での登録と、サーバーからの取り消し・変更で締める。
/// スクリーンショット番号とバリアントの対応は scripts/generate_screenshots/appstore_screenshot_env.sh の get_variant_name が正

/// 訴求軸 signal のレイアウトコンテナ
struct AppStoreScreenshotSignalLayout<Content: View>: View {
    /// メインのキャッチコピー
    let title: Text
    /// サブコピー (二次テキスト 70% 紙色)
    let subtitle: LocalizedStringResource
    /// デバイスフレーム内に表示するモック画面
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.night

            // 左上から差し込むシグナルの微光 (アイコンの橙アークと同モチーフ)。コピーの可読性を優先して淡く敷く
            RadialGradient(
                colors: [Color.signal.opacity(0.28), Color.signal.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )

            VStack(spacing: 0) {
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
                .padding(.top, 56)
                .padding(.horizontal, 28)
                // 見出し 2 行 + サブコピー 2 行分の高さで固定し、行数の差でデバイスフレームの位置と大きさがページごとに変わらないようにする
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)

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
        .ignoresSafeArea()
    }
}

/// App Store スクリーンショット 1 枚目 - signal - Webhook が本物のアラームになる (コアコンセプト)
struct AppStoreScreenshot1Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: Webhook を
            //
            // 本物のアラームに
            title: Text("Webhooks become\nreal alarms"),
            // ja: HTTP リクエストひとつで
            //
            // iPhone のアラームが鳴る
            subtitle: "One HTTP request and your iPhone rings"
        ) {
            MockAlarmRingingScreen(
                // ja: デプロイ完了
                title: Text("Deploy finished"),
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
                // ja: サーバーダウン
                title: Text("Server down"),
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
            // ja: GitHub Actions も Home Assistant も
            //
            // cron も curl も
            subtitle: "GitHub Actions, Home Assistant, cron, Zapier and plain curl"
        ) {
            MockIntegrationsScreen()
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
            // あとは Alarmify が届ける
            subtitle: "Send a time and a title and Alarmify does the rest"
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

/// App Store スクリーンショット 5 枚目 - signal - 取り消しも変更もサーバーから
struct AppStoreScreenshot5Page: View {
    var body: some View {
        AppStoreScreenshotSignalLayout(
            // ja: 取り消しも変更も
            //
            // サーバーから
            title: Text("Cancel or change\nfrom your server"),
            // ja: 登録と発火の履歴は
            //
            // アプリで確認できる
            subtitle: "Every alarm keeps a history you can check in the app"
        ) {
            MockHomeScreen()
        }
    }
}

/// AppStoreScreenshot5Page の Preview。UITest (SnapshotUITest wrapper) の撮影対象
struct AppStoreScreenshot5Page_Previews: PreviewProvider {
    static var previews: some View {
        AppStoreScreenshot5Page().environment(\.colorScheme, .dark)
    }
}
