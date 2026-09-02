import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// AlarmKit のアラーム (カウントダウン・鳴動) のロック画面 / Dynamic Island 表示。
/// アラーム鳴動時はシステムが AlarmPresentation.Alert を優先描画するため、カスタム View は最小限にする
struct AlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmifyAlarmMetadata>.self) { context in
            VStack(spacing: 8) {
                if let title = context.attributes.metadata?.title {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                if case .countdown(let countdown) = context.state.mode {
                    Text(countdown.fireDate, style: .timer)
                        .font(.title2)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    if let title = context.attributes.metadata?.title {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    if case .countdown(let countdown) = context.state.mode {
                        Text(countdown.fireDate, style: .timer)
                            .font(.title2)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "alarm")
            }
            .keylineTint(context.attributes.tintColor)
        }
    }
}
