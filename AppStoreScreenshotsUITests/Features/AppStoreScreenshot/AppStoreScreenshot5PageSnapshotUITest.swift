import XCTest

/// AppStoreScreenshot5Page を全対象言語で撮影する SnapshotUITest。
/// XCTAttachment 名 ({file}---{function}---{language}---{index}) を
/// scripts/generate_screenshots/organize_appstore_screenshots.sh が解析して fastlane 形式に整理する
final class AppStoreScreenshot5PageSnapshotUITest: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // runsForEachTargetApplicationUIConfiguration で実行すると Locale の取得がうまくいかず全部 en になる (取り込み元での実測)
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 撮影対象の PreviewProvider 名。AppStoreScreenshotsRootPage のボタンラベルと一致させる
    let previewType = "AppStoreScreenshot5Page_Previews"
    /// PreviewProvider が持つ Preview の個数。_allPreviews を型から辿れないためハードコードする
    let previewCount = 1

    func testSnapshot() throws {
        // スクショページはダークモード前提のため、ステータスバー等の描画も dark に固定する
        XCUIDevice.shared.appearance = .dark
        let fileName = URL(fileURLWithPath: #file).deletingPathExtension().lastPathComponent
        let functionName = #function.replacingOccurrences(of: "()", with: "")

        filteredLanguages().forEach { (language, languageWithRegion) in
            debugPrint("Start: ", #file, #function, language)

            let app = XCUIApplication.instantiate()
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
            // 日付等のロケール依存表示を対象地域の形式で撮影するため、リージョン付きタグも渡す
            app.launchArguments += ["-AppleLocale", languageWithRegion]

            for index in (0..<previewCount) {
                // 遷移先の Preview には戻るボタンが無い (navigationBarBackButtonHidden) ため、
                // index ごとに起動し直して一覧画面から次の Preview をタップする (launch は起動中のアプリを終了してから起動する)
                app.launch()

                let button = app.buttons["\(previewType)_\(index)"].firstMatch
                // 一覧の下部にあるボタンは初期表示領域外になり得るため、hittable になるまでスクロールしてからタップする
                var swipeCount = 0
                while !button.isHittable && swipeCount < 5 {
                    app.swipeUp()
                    swipeCount += 1
                }
                button.tap()
                // 遷移先の Preview が表示されたことを確認してから撮影する (一覧のまま撮影して成功にしない)
                XCTAssertTrue(
                    app.descendants(matching: .any)["SnapshotPreview_\(previewType)_\(index)"]
                        .waitForExistence(timeout: 5)
                )
                // push 遷移のアニメーションの完了と、ホームインジケーターの自動非表示
                // (persistentSystemOverlays(.hidden) は自動非表示の許可で、最終タッチから数秒後に消える) を待って撮影する
                sleep(6)

                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "\(fileName)---\(functionName)---\(language)---\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
