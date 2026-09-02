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
    /// 開発者メニューで接続先を変えた後、再起動するまで反映されない状態かどうか。
    /// Firebase Auth の向き先 (エミュレータ / 本番) は起動時にしか決められないため、切り替えは再起動を待つ
    private(set) var backendChangePendingRestart = false

    /// 接続先とスタブ利用の設定。開発者メニューから変更されたら API クライアントを作り直す
    private(set) var settings: DeveloperSettings
    private var apiClient: AlarmifyAPIClient

    /// 既定は保存済みの開発者設定から作る。テストは設定を直接渡して UserDefaults に触れずに組み立てる
    init(settings: DeveloperSettings = DeveloperMenu.settings) {
        self.settings = settings
        self.apiClient = Self.makeAPIClient(settings: settings)
    }

    /// 匿名認証でサインインする。既にサインイン済みなら既存のアカウントをそのまま使う (再インストールを跨いだ復元は Firebase Auth の keychain 永続化に任せる)。
    /// 起動時のほか、前面復帰と画面からの再試行でも呼ぶ (一過性のネットワークエラーで永久にサインインできないままにしないため)
    func signIn() async {
        if let user = Auth.auth().currentUser {
            // 再インストール後は keychain のアカウントだけが残り App Group の値は消えるため、どの接続先のものかをここで記録し直す
            if DeveloperMenu.authenticatedBackend == nil {
                DeveloperMenu.authenticatedBackend = settings.backend
            }
            uid = user.uid
            signInError = nil
            await registerDeviceIfPossible()
            return
        }
        do {
            let result = try await Auth.auth().signInAnonymously()
            DeveloperMenu.authenticatedBackend = settings.backend
            uid = result.user.uid
            signInError = nil
        } catch {
            signInError = error.localizedDescription
            Logger.push.error("Anonymous sign-in failed: \(error.localizedDescription)")
            return
        }
        // サインインの完了前に FCM トークンが届いていた場合、その登録はここで初めて成立する
        await registerDeviceIfPossible()
    }

    /// FCM 登録トークンを受け取り、サインイン済みならバックエンドへ登録する
    func register(fcmRegistrationToken: String) async {
        self.fcmRegistrationToken = fcmRegistrationToken
        await registerDeviceIfPossible()
    }

    /// 画面からの再試行。サインインが済んでいなければサインインからやり直す
    func retryDeviceRegistration() async {
        await signIn()
    }

    /// 開発者メニューからの設定変更を反映する。
    /// 接続先の変更は Firebase Auth の向き先を伴うため保存だけ行い、反映は次の起動に委ねる
    /// (今の実行中に差し替えると、本番の ID トークンをエミュレータへ送る等のちぐはぐな組み合わせになる)
    func apply(settings: DeveloperSettings) async {
        let backendChanged = settings.backend != self.settings.backend
        DeveloperMenu.settings = settings
        backendChangePendingRestart = backendChanged
        guard !backendChanged else { return }
        self.settings = settings
        apiClient = Self.makeAPIClient(settings: settings)
        // スタブで受けていた登録は実クライアントには届いていないため、差し替え後の相手へ登録し直す
        deviceRegistration = .notRegistered
        await registerDeviceIfPossible()
    }

    /// API トークン画面が使う呼び出し口。設定に応じた実装を返す
    var client: AlarmifyAPIClient { apiClient }

    /// アカウントとサーバー上のデータを削除し、アプリを初回起動と同じ状態 (新しい匿名アカウント) に戻す。
    /// 端末内の AlarmKit のアラームには触れない (公開している削除手順の記載と揃える)。
    /// サーバーの削除に失敗した場合はサインイン状態を変えずにエラーを投げる (削除できていないアカウントを画面から消さない)
    func deleteAccount() async throws {
        do {
            try await apiClient.deleteAccount()
        } catch where Self.isAccountAlreadyGone(error) {
            // 前回の削除がサーバーで成功して応答だけ失われた後の再試行。Auth のユーザーが無いため ID トークンを
            // 取得し直せず Callable まで届かないが、削除自体は完了しているので端末側の状態だけ揃える
        }
        // スタブは実際には何も削除していないため、Firebase Auth の実アカウントを捨てない (画面のフローの確認だけに使う)
        guard !settings.stubAPIClient else { return }
        // 削除済みのユーザーの認証状態を keychain に残さない。消せなかった場合はそのユーザーで signIn() し直してしまうため先へ進まない
        try Auth.auth().signOut()
        DeveloperMenu.authenticatedBackend = nil
        uid = nil
        deviceRegistration = .notRegistered
        await signIn()
    }

    /// ID トークンの取得時にサーバー側のアカウントが既に無いと判明したか。
    /// Firebase Auth は refresh で user-not-found を受けるとそのユーザーをサインアウトするため、未サインインもこの状態に含める
    private static func isAccountAlreadyGone(_ error: Error) -> Bool {
        if case .notSignedIn? = error as? AlarmifyAPIError { return true }
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return false }
        return nsError.code == AuthErrorCode.userNotFound.rawValue || nsError.code == AuthErrorCode.userTokenExpired.rawValue
    }

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
