import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit のアラーム (カウントダウン・鳴動) のロック画面 / Dynamic Island 表示。
/// アラーム鳴動時はシステムが AlarmPresentation.Alert を優先描画するため、カスタム View は最小限にする。
/// 配色は design_handoff/screens/lock-screen.md に従い、地は常に暗い (`activityBackgroundTint`) ため文字色も端末の外観に追従させず固定する
struct AlarmLiveActivityWidget: Widget {
    /// 暗い地の上の一次テキスト (`paper` のダーク値)。ライト外観でも黒地に黒文字にならないよう固定する
    private static let foreground = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF0 / 255)
    /// 暗い地の上の補助テキスト (`paperTertiary` のダーク値)
    private static let secondaryForeground = foreground.opacity(0.56)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmifyAlarmMetadata>.self) { context in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 4) {
                    // 製品名の表示。翻訳対象ではないため verbatim
                    Text(verbatim: "SIGNALARM")
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Self.secondaryForeground)
                    if let title = context.attributes.metadata?.title {
                        // 外部サービスから送られたタイトルはそのまま表示する
                        Text(verbatim: title)
                            .font(.headline)
                            .foregroundStyle(Self.foreground)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                modeText(context.state.mode)
                    .font(.title2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let title = context.attributes.metadata?.title {
                        Text(verbatim: title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    modeText(context.state.mode)
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(context.attributes.tintColor)
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                modeText(context.state.mode)
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
            } minimal: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    /// 状態ごとの右側の表示。カウントダウン中は残り時間、鳴動中は時刻 (システムの発火 UI が前面に出る間の補助表示)、一時停止中はその旨
    @ViewBuilder
    private func modeText(_ mode: AlarmPresentationState.Mode) -> some View {
        switch mode {
        case .countdown(let countdown):
            Text(countdown.fireDate, style: .timer)
        case .alert:
            Image(systemName: "bell.and.waves.left.and.right.fill")
        case .paused:
            Image(systemName: "pause.fill")
        @unknown default:
            EmptyView()
        }
    }
}
