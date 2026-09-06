import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit のアラーム (カウントダウン・鳴動) のロック画面 / Dynamic Island 表示。
/// アラーム鳴動時はシステムが AlarmPresentation.Alert を優先描画するため、カスタム View は最小限にする。
/// 配色はストア素材・アプリアイコンと同じシグナル橙 (`Color.signal`) に揃え、受領デザイン (#6) の反映時に見直す
struct AlarmLiveActivityWidget: Widget {
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
                        .foregroundStyle(.secondary)
                    if let title = context.attributes.metadata?.title {
                        // 外部サービスから送られたタイトルはそのまま表示する
                        Text(verbatim: title)
                            .font(.headline)
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
