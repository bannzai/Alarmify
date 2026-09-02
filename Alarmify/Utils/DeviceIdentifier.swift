import Foundation
import UIKit

/// バックエンドへ端末を登録する時の `device_id` (`POST /v1/devices`)。
/// 同じ端末からの再登録が上書きになるよう、アプリの起動を跨いで同じ値を返す
enum DeviceIdentifier {
    private static let key = "deviceIdentifier"

    /// この端末の識別子。初回に解決した値を App Group の UserDefaults に保存し、以降はそれを返す (冪等)。
    /// `identifierForVendor` はロック中などに nil になることがあるため、取れない時は生成した UUID で代替する
    static var current: String {
        let defaults = AppGroup.userDefaults
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        defaults.set(identifier, forKey: key)
        return identifier
    }
}
