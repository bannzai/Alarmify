import SwiftUI
import WidgetKit

/// AlarmifyWidget Extension のエントリポイント
@main
struct AlarmifyWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmLiveActivityWidget()
    }
}
