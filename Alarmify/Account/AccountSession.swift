import FirebaseAuth
import Foundation
import Observation
import os

/// この端末の配送先 (FCM 登録トークン) をバックエンドへ登録した状態
enum DeviceRegistrationState: Equatable, Sendable {
    case notRegistered
    case registering
    case registered
    /// 失敗したエラーの説明。サーバーのメッセージをそのまま持つ
    case failed(String)
}

/// 匿名認証で自動作成したアカウントと、この端末の配送先登録をまとめて持つ。
/// FCM トークンの受信は `AppDelegate`、表示は SwiftUI と入口が分かれるため 1 インスタンス (`shared`) に集約する
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    /// 匿名認証で作られたアカウントの uid。未サインインなら nil
    private(set) var uid: String?
    /// FCM の登録トークン。simulator でも取得できるが、実際の配送には APNs キーの登録が要る
    private(set) var fcmRegistrationToken: String?
    private(set) var deviceRegistration: DeviceRegistrationState = .notRegistered
    /// サインインに失敗したエラーの説明。成功したら nil に戻す
    private(set) var signInError: String?

    /// 接続先とスタブ利用の設定。開発者メニューから変更されたら API クライアントを作り直す
    private(set) var settings: DeveloperSettings
    private var apiClient: AlarmifyAPIClient

    /// 既定は保存済みの開発者設定から作る。テストは設定を直接渡して UserDefaults に触れずに組み立てる
    init(settings: DeveloperSettings = DeveloperMenu.settings) {
        self.settings = settings
        self.apiClient = Self.makeAPIClient(settings: settings)
    }

    /// 匿名認証でサインインする。既にサインイン済みなら既存のアカウントをそのまま使う (再インストールを跨いだ復元は Firebase Auth の keychain 永続化に任せる)
    func signIn() async {
        if let user = Auth.auth().currentUser {
            uid = user.uid
            signInError = nil
            return
        }
        do {
            let result = try await Auth.auth().signInAnonymously()
            uid = result.user.uid
            signInError = nil
        } catch {
            signInError = error.localizedDescription
            Logger.push.error("Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    /// FCM 登録トークンを受け取り、サインイン済みならバックエンドへ登録する
    func register(fcmRegistrationToken: String) async {
        self.fcmRegistrationToken = fcmRegistrationToken
        await registerDeviceIfPossible()
    }

    /// 画面からの再試行。トークンが未取得なら何もしない
    func retryDeviceRegistration() async {
        await registerDeviceIfPossible()
    }

    /// 開発者メニューからの設定変更を反映する。API クライアントを作り直し、登録状態を初期化する
    func apply(settings: DeveloperSettings) {
        DeveloperMenu.settings = settings
        self.settings = settings
        apiClient = Self.makeAPIClient(settings: settings)
        deviceRegistration = .notRegistered
    }

    /// API トークン画面が使う呼び出し口。設定に応じた実装を返す
    var client: AlarmifyAPIClient { apiClient }

    private func registerDeviceIfPossible() async {
        guard let fcmRegistrationToken else { return }
        deviceRegistration = .registering
        do {
            try await apiClient.registerDevice(fcmRegistrationToken: fcmRegistrationToken)
            deviceRegistration = .registered
        } catch {
            deviceRegistration = .failed(error.localizedDescription)
            Logger.push.error("Registering device failed: \(error.localizedDescription)")
        }
    }

    private static func makeAPIClient(settings: DeveloperSettings) -> AlarmifyAPIClient {
        if settings.stubAPIClient {
            return StubAlarmifyAPIClient()
        }
        return URLSessionAlarmifyAPIClient(backend: settings.backend) {
            guard let user = Auth.auth().currentUser else { return nil }
            return try await user.getIDToken()
        }
    }
}
