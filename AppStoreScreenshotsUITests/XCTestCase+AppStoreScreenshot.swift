import XCTest

extension XCTestCase {
    /// 表示中のページを App Store スクリーンショット 1 枚として撮影する。
    /// `XCTAttachment(screenshot:)` で画面を添付する (name は organize_appstore_screenshots.sh が解析する `{class}---{function}---{language}---{index}` 形式)。
    /// 環境変数 `SNAPSHOT_HOST_CAPTURE_DIR` がある時は、そのディレクトリに `{name}.ready` を書き、
    /// ホスト側 (scripts/generate_screenshots/generate_duo_screenshots.sh) が `{name}.done` を書くまで待つ。
    /// iPhone Duo の内側ディスプレイは XCTest の API では App Store の仕様の寸法で撮れず、
    /// ホストの `xcrun simctl io <UDID> screenshot --display=primary-1` で撮る必要があるため
    /// (appstore-screenshot-builder skill の references/iphone-duo.md)。
    /// simulator のテストランナーはホストのファイルシステムに書けるため、ファイルで同期する
    func attachAppStoreScreenshot(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let hostCaptureDirectoryPath = ProcessInfo.processInfo.environment["SNAPSHOT_HOST_CAPTURE_DIR"],
              !hostCaptureDirectoryPath.isEmpty else {
            return
        }
        let hostCaptureDirectoryURL = URL(fileURLWithPath: hostCaptureDirectoryPath)
        let doneFilePath = hostCaptureDirectoryURL.appendingPathComponent("\(name).done").path
        FileManager.default.createFile(atPath: hostCaptureDirectoryURL.appendingPathComponent("\(name).ready").path, contents: nil)

        // ホストの 1 枚の撮影 (simctl screenshot と alpha の除去) は数秒で終わる。
        // Mac の負荷が高い時の遅れを見込んで余裕を持たせ、それでも来なければホストが止まっているとみなす
        let deadline = Date.now.addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: doneFilePath) {
            if Date.now > deadline {
                XCTFail("ホストの撮影完了 (\(doneFilePath)) が 120 秒以内に来なかった")
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
