import Foundation

/// ユニットテスト実行中かどうか。XCTest のバンドルが読み込まれているかで判定する
var isUnitTest: Bool {
    NSClassFromString("XCTestCase") != nil
}

/// SwiftUI の Preview 実行中かどうか
var isPreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
