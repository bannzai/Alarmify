import SwiftUI

/// 外部サービスから登録されたアラームが鳴っている瞬間のモック。
/// AlarmKit の全画面アラート (時刻 + タイトル + 停止) を、ロック画面の空気で再現する。
/// 本番アプリにはまだ鳴動画面の実装が無いため、スクリーンショット専用のモック UI として実装する
/// (appstore-screenshot-builder skill「コンテンツ作成の優先順位」の最終手段)
struct MockAlarmRingingScreen: View {
    /// 外部サービスが送ってきたアラームのタイトル。翻訳されずそのまま届くため、呼び出し側は verbatim で渡す
    let title: Text
    /// 送信元 (サービス名・環境)。ブランド名を含むため verbatim で渡す
    let source: Text
    /// true なら集中モード・消音の状態表示を上部に重ね、「それでも鳴る」ことを見せる
    var showsFocusBadges = false

    var body: some View {
        VStack(spacing: 0) {
            if showsFocusBadges {
                HStack(spacing: 10) {
                    // ja: おやすみモード
                    focusBadge(systemName: "moon.fill", label: Text("Do Not Disturb"))
                    // ja: 消音
                    focusBadge(systemName: "bell.slash.fill", label: Text("Silent"))
                }
                .padding(.top, 60)
            }

            VStack(spacing: 6) {
                // ja: 9月2日 水曜日
                Text("Wednesday, September 2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.paper.opacity(0.6))
                // 時刻はロケール非依存の視覚要素のため verbatim
                Text(verbatim: "3:07")
                    .font(.system(size: 96, weight: .thin))
                    .foregroundStyle(Color.paper)
            }
            .padding(.top, showsFocusBadges ? 28 : 96)

            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.signal)
                    Text(verbatim: "SIGNALARM")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(Color.paper.opacity(0.6))
                }
                title
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.paper)
                source
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.paper.opacity(0.55))
            }
            .padding(.horizontal, 32)

            Spacer()

            // ja: 停止
            MockPillLabel(label: Text("Stop"))
                .padding(.horizontal, 48)
                // デバイスフレームの下端は画面外に切れるため、停止ボタンは切れない高さに置く
                .padding(.bottom, 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night)
    }

    /// 集中モード・消音の状態を示す pill
    private func focusBadge(systemName: String, label: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
            label
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.paper.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.paper.opacity(0.12)))
    }
}
