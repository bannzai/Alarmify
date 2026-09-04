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
    /// 実行中・実行待ちの端末登録。登録は同じ device_id を書き換えるため直列に行う
    private var registration: Task<Void, Never>?

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
            await registerDeviceAndLinkPurchases(uid: user.uid)
            return
        }
        let signedInUid: String
        do {
            let result = try await Auth.auth().signInAnonymously()
            DeveloperMenu.authenticatedBackend = settings.backend
            signedInUid = result.user.uid
            uid = signedInUid
            signInError = nil
        } catch {
            signInError = error.localizedDescription
            Logger.push.error("Anonymous sign-in failed: \(error.localizedDescription)")
            return
        }
        await registerDeviceAndLinkPurchases(uid: signedInUid)
    }

    /// 配送先の登録と RevenueCat の identity 連携を並行して行う。
    /// RevenueCat の応答を待つ間に配送先の登録 (サインインの完了前に届いていた FCM トークンの登録を含む) を遅らせない
    private func registerDeviceAndLinkPurchases(uid: String) async {
        let linking = Task { @MainActor [weak self] in
            await self?.linkPurchases(uid: uid)
        }
        await registerDeviceIfPossible()
        await linking.value
    }

    /// サインイン済みの uid を RevenueCat の App User ID にする。
    /// 本番の Firestore を更新する RevenueCat の webhook には接続先の区別が無いため、エミュレータ向けのアカウント
    /// (本番に存在しない uid) では結び付けず、購入を RevenueCat の匿名 ID のまま残す (webhook 側で無視される)。
    /// 本番からエミュレータへ切り替えた起動では、残っている本番の identity での購入が本番の Firestore を更新しないよう、匿名 ID に戻す
    private func linkPurchases(uid: String) async {
        guard settings.backend == .production else {
            await ProEntitlement.logOut()
            return
        }
        await ProEntitlement.logIn(appUserID: uid)
    }

    /// ペイウォールの購入・復元の直前に呼び、購入が uid に結び付く状態かを返す。
    /// 起動時の logIn が失敗したまま匿名 ID で購入すると、webhook に uid が載らずサーバーのプランが更新されないため、
    /// ここで結び付けをやり直し、できなければ購入を始めない。エミュレータ向けのアカウントは結び付けない設計のため常に true
    func ensurePurchasesLinked() async -> Bool {
        guard settings.backend == .production else { return true }
        guard let uid else { return false }
        await ProEntitlement.logIn(appUserID: uid)
        return ProEntitlement.isLoggedIn(as: uid)
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
            // 取得し直せず Callable まで届かないが、サーバーがアカウントの不在を返しているので端末側の状態だけ揃える
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

    /// ID トークンの取得時に、サーバー側のアカウントが既に無いことが確認できたか。
    /// 判定に使うのは Firebase Auth が refresh で受け取った user-not-found だけにする
    /// (userTokenExpired 等の失効・取り消しはアカウントが残っていても起きるため、削除の完了とはみなさない)
    private static func isAccountAlreadyGone(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == AuthErrorDomain && nsError.code == AuthErrorCode.userNotFound.rawValue
    }

    /// 起動時の登録とトークンのローテーションが重なると、同じ device_id への登録が並行して走る。
    /// 先に送った古いトークンの登録が後から着くとバックエンドを古い値で上書きしてしまうため、直前の登録の完了を待ってから始める
    private func registerDeviceIfPossible() async {
        let previous = registration
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.registerDevice()
        }
        registration = task
        await task.value
    }

    private func registerDevice() async {
        // FCM の delegate は起動のたびに呼ばれるとは限らない (新規取得とローテーション時だけ)。
        // 受信済みのトークンが保存されていればそれで登録し、再起動後の再試行が空振りしないようにする。
        // 直列化した後に読むことで、待っている間に届いた新しいトークンで登録する
        guard let fcmRegistrationToken = fcmRegistrationToken ?? DeviceTokenStore.loadFCMRegistrationToken() else { return }
        self.fcmRegistrationToken = fcmRegistrationToken
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
