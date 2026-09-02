import Foundation

/// 動作確認のために切り替える設定。App Store 配布では解放せず、DEBUG ビルドと TestFlight 配布でのみ変更できる
/// (`.claude/rules/debug-menu-for-verification.md`)
struct DeveloperSettings: Equatable, Sendable {
    /// アプリが接続するバックエンド
    var backend: AlarmifyBackend
    /// バックエンド未起動でも API トークンの一覧・発行・失効の画面を確認できるよう、通信をメモリ上のスタブへ差し替える
    var stubAPIClient: Bool

    static let `default` = DeveloperSettings(backend: .production, stubAPIClient: false)
}

/// 開発者メニューの解放判定と `DeveloperSettings` の永続化。
/// 解放されていない配布 (App Store) では常に既定値を返し、保存も行わない
enum DeveloperMenu {
    private static let backendKey = "developerBackend"
    private static let stubAPIClientKey = "developerStubAPIClient"
    private static let authenticatedBackendKey = "developerAuthenticatedBackend"

    /// 開発者メニューを表示してよいか。TestFlight は App Store と同じ Release バイナリのためレシート名で判定する
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Firebase Auth の keychain に残っているアカウントがどの接続先のものか。未サインインなら nil。
    /// 本番とエミュレータのアカウントは互換性が無いため、接続先を切り替えた起動ではこの値と比較してサインアウトする
    static var authenticatedBackend: AlarmifyBackend? {
        get { AppGroup.userDefaults.string(forKey: authenticatedBackendKey).flatMap(AlarmifyBackend.init(rawValue:)) }
        set { AppGroup.userDefaults.set(newValue?.rawValue, forKey: authenticatedBackendKey) }
    }

    /// 保存済みの設定。解放されていなければ既定値
    static var settings: DeveloperSettings {
        get {
            guard isAvailable else { return .default }
            let defaults = AppGroup.userDefaults
            let backend = defaults.string(forKey: backendKey).flatMap(AlarmifyBackend.init(rawValue:)) ?? DeveloperSettings.default.backend
            return DeveloperSettings(backend: backend, stubAPIClient: defaults.bool(forKey: stubAPIClientKey))
        }
        set {
            guard isAvailable else { return }
            let defaults = AppGroup.userDefaults
            defaults.set(newValue.backend.rawValue, forKey: backendKey)
            defaults.set(newValue.stubAPIClient, forKey: stubAPIClientKey)
        }
    }
}
