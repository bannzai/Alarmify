import AuthenticationServices
import CryptoKit
import FirebaseAppCheck
import FirebaseAuth
import Foundation
import Observation
import os
import UIKit

/// この端末の配送先 (FCM 登録トークン) をバックエンドへ登録した状態
enum DeviceRegistrationState: Equatable, Sendable {
    case notRegistered
    case registering
    case registered
    /// 失敗したエラーの説明。サーバーのメッセージをそのまま持つ
    case failed(String)
}

/// 購入・復元を始める前の、RevenueCat の identity と Firebase Auth の uid の結び付きの状態 (`AccountSession.purchaseLinkState`)。
/// 表示する文言は使用側 (PaywallPage) が switch で決める
enum PurchaseLinkState: Equatable, Sendable {
    /// uid に結び付いていて購入を始めてよい
    case linked
    /// 結び付けに失敗した (未サインイン・RevenueCat の logIn の失敗)
    case notLinked
    /// 接続先がエミュレータで、購入・復元を許さない
    case emulatorBackend
}

/// Sign in with Apple の結果から Firebase Auth へ渡す値を取り出せなかった理由
enum AppleSignInError: LocalizedError {
    /// Apple の認証情報に identity token が含まれていない
    case missingIdentityToken
    /// Apple の認証情報に authorization code が含まれていない (トークンの失効に使う)
    case missingAuthorizationCode
    /// ボタンの結果が届いた時に、リクエストへ設定した nonce が残っていない
    case missingNonce

    var errorDescription: String? {
        // ja: Apple でのサインインを完了できませんでした
        String(localized: "Couldn't complete Sign in with Apple")
    }
}

/// 匿名認証で自動作成したアカウント (Sign in with Apple でリンク・統合したものを含む) と、この端末の配送先登録をまとめて持つ。
/// FCM トークンの受信は `AppDelegate`、表示は SwiftUI と入口が分かれるため 1 インスタンス (`shared`) に集約する
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    /// サインイン中のアカウントの uid (匿名、または Sign in with Apple のアカウント)。未サインインなら nil
    private(set) var uid: String?
    /// サインイン中のアカウントに Apple の認証情報がリンクされているか。
    /// リンク済みなら別の iPhone から同じ Apple アカウントでサインインして、同じ uid (API トークン・登録端末) を使える
    private(set) var appleIDLinked = false
    /// Sign in with Apple の処理中か。ボタンの二重タップを防ぎ、進行中の表示に使う
    private(set) var appleSignInInProgress = false
    /// Sign in with Apple (匿名アカウントの統合を含む) に失敗したエラーの説明。成功したら nil に戻す
    private(set) var appleSignInError: String?
    /// FCM の登録トークン。simulator でも取得できるが、実際の配送には APNs キーの登録が要る
    private(set) var fcmRegistrationToken: String?
    private(set) var deviceRegistration: DeviceRegistrationState = .notRegistered
    /// 適用結果の報告をバックエンドへ最後に送れた時刻。サーバーの履歴 (`device_reports`) が変わった合図としてホームが購読する。未送信なら nil
    private(set) var alarmApplyReportsFlushedAt: Date?
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
    /// 表示中の Sign in with Apple のリクエストに設定した nonce の原文。Apple へはハッシュを渡し、Firebase Auth へは原文を渡して照合させる
    private var appleIDRequestNonce: String?
    /// 既存の Apple アカウントへ切り替えた後、まだバックエンドで統合できていない匿名アカウントの ID トークン。
    /// 切り替えた後は匿名アカウントの ID トークンを取り直せないため保持し、失敗したら次の signIn (起動・前面復帰) で送り直す。
    /// アプリが終了しても送り直せるよう keychain に保存する
    private var pendingAnonymousMergeIDToken: String? {
        get { PendingAnonymousMergeIDTokenStore.load() }
        set { PendingAnonymousMergeIDTokenStore.save(newValue) }
    }

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
            appleIDLinked = Self.hasAppleID(user: user)
            signInError = nil
            await mergePendingAnonymousAccount()
            await registerDeviceAndLinkPurchases(uid: user.uid)
            await syncPendingPurchases(uid: user.uid)
            return
        }
        let signedInUid: String
        do {
            let result = try await Auth.auth().signInAnonymously()
            DeveloperMenu.authenticatedBackend = settings.backend
            signedInUid = result.user.uid
            uid = signedInUid
            appleIDLinked = false
            signInError = nil
        } catch {
            signInError = error.localizedDescription
            Logger.push.error("Anonymous sign-in failed: \(error.localizedDescription)")
            return
        }
        await registerDeviceAndLinkPurchases(uid: signedInUid)
    }

    // MARK: - Sign in with Apple

    /// Sign in with Apple のボタンが作るリクエストに nonce を設定する。
    /// nonce は identity token の使い回しを防ぐため Firebase Auth が照合する値で、リクエストのたびに作り直す
    func prepare(appleIDRequest: ASAuthorizationAppleIDRequest) {
        let nonce = Self.makeNonce()
        appleIDRequestNonce = nonce
        // メールアドレスと氏名は使わないため要求しない (Firebase Auth に保持させず、App Privacy の回答を増やさない。documents/app-privacy.md)
        appleIDRequest.requestedScopes = []
        appleIDRequest.nonce = Self.sha256(nonce: nonce)
    }

    /// Sign in with Apple のボタンの結果でサインインする。
    /// 匿名アカウントに Apple の認証情報をリンクして uid を維持し、その Apple アカウントが既に別の uid で使われていれば
    /// Apple 側の uid へ切り替えて、匿名側の端末をバックエンドで移す (API トークンと当月の利用数は Apple 側のものを使う)。
    /// ユーザーがシートを閉じた時は何もしない
    func completeSignInWithApple(result: Result<ASAuthorization, Error>) async {
        let nonce = appleIDRequestNonce
        appleIDRequestNonce = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                appleSignInError = error.localizedDescription
                Logger.account.error("Sign in with Apple failed: \(error.localizedDescription)")
            }
        case .success(let authorization):
            appleSignInInProgress = true
            defer { appleSignInInProgress = false }
            do {
                guard let nonce else { throw AppleSignInError.missingNonce }
                try await signInWithApple(authorization: authorization, rawNonce: nonce)
                // 統合の送信に失敗した時は mergePendingAnonymousAccount が設定したエラーを残す
                if pendingAnonymousMergeIDToken == nil {
                    appleSignInError = nil
                }
            } catch {
                appleSignInError = error.localizedDescription
                Logger.account.error("Sign in with Apple failed: \(error.localizedDescription)")
            }
        }
    }

    /// Apple の認証情報を Firebase Auth の認証情報にして、リンク・既存アカウントへの切り替え・そのままのサインインのどれかを行う
    private func signInWithApple(authorization: ASAuthorization, rawNonce: String) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
        else { throw AppleSignInError.missingIdentityToken }
        let credential = OAuthProvider.appleCredential(withIDToken: identityToken, rawNonce: rawNonce, fullName: nil)
        guard let currentUser = Auth.auth().currentUser else {
            // 匿名認証に失敗したまま (オフラインで起動した等) の状態。統合する匿名アカウントが無いため Apple のアカウントでそのままサインインする
            let result = try await Auth.auth().signIn(with: credential)
            DeveloperMenu.authenticatedBackend = settings.backend
            await switchAccount(uid: result.user.uid)
            return
        }
        do {
            _ = try await currentUser.link(with: credential)
            appleIDLinked = true
        } catch let error as NSError
            where currentUser.isAnonymous
            && error.domain == AuthErrorDomain
            && error.code == AuthErrorCode.credentialAlreadyInUse.rawValue
        {
            // この Apple アカウントは別の uid で使われている。identity token は 1 度しか使えないため、Firebase Auth がエラーに添える認証情報でサインインする
            guard let existingAccountCredential = error.userInfo[AuthErrors.userInfoUpdatedCredentialKey] as? AuthCredential else { throw error }
            // サインインを切り替えると匿名アカウントの ID トークンを取り直せないため、先に取っておく
            pendingAnonymousMergeIDToken = try await currentUser.getIDToken()
            let result = try await Auth.auth().signIn(with: existingAccountCredential)
            await switchAccount(uid: result.user.uid)
        }
    }

    /// Apple のアカウントへ切り替えた後に、統合・端末登録・購入の結び付けをやり直す。
    /// 購入は RevenueCat の logIn だけでは元の App User ID (匿名アカウントの uid) に残るため、StoreKit の購入を送り直して
    /// プロジェクトの restore behavior (既定の Transfer to new App User ID) で Apple 側の uid へ移す
    /// ( https://www.revenuecat.com/docs/projects/restore-behavior )。移った購入は webhook の TRANSFER が users/{uid}.plan に反映する
    private func switchAccount(uid newUid: String) async {
        uid = newUid
        appleIDLinked = true
        signInError = nil
        deviceRegistration = .notRegistered
        UserDefaults.standard.set(newUid, forKey: .pendingPurchaseSyncAppUserID)
        await mergePendingAnonymousAccount()
        await registerDeviceAndLinkPurchases(uid: newUid)
        await syncPendingPurchases(uid: newUid)
    }

    /// アカウントを切り替えた後の購入の送り直しが済んでいなければ行う。送り直せたら記録を消し、失敗したら次の signIn (起動・前面復帰) でやり直す。
    /// RevenueCat の logIn は失敗を内部で握りつぶすため、今の App User ID がこの uid になったことを確かめてから送る
    /// (前の uid のまま送ると、購入が切り替え先へ移らない)。何度呼んでも、送り直しが済んだ状態に収束する
    private func syncPendingPurchases(uid: String) async {
        guard UserDefaults.standard.string(forKey: .pendingPurchaseSyncAppUserID) == uid else { return }
        // エミュレータ向けのアカウントは RevenueCat に結び付けない (linkPurchases) ため、送り直す先が無い
        guard settings.backend == .production else {
            UserDefaults.standard.removeObject(forKey: .pendingPurchaseSyncAppUserID)
            return
        }
        guard ProEntitlement.isLoggedIn(as: uid), await ProEntitlement.syncPurchases() else { return }
        UserDefaults.standard.removeObject(forKey: .pendingPurchaseSyncAppUserID)
    }

    /// 切り替える前の匿名アカウントの端末を Apple 側へ移し、匿名アカウントをバックエンドで削除する。
    /// 送れたか、送り直しても受け付けられない (ID トークンの期限切れ等) ならトークンを捨て、通信エラー等は次の signIn で送り直す。
    /// サーバー側が冪等なため、何度呼んでも同じ状態になる
    private func mergePendingAnonymousAccount() async {
        guard let pendingAnonymousMergeIDToken else { return }
        do {
            try await apiClient.mergeAnonymousAccount(anonymousIDToken: pendingAnonymousMergeIDToken)
            self.pendingAnonymousMergeIDToken = nil
            appleSignInError = nil
        } catch let error as AlarmifyAPIError where error.rejectsAnonymousAccountMerge {
            self.pendingAnonymousMergeIDToken = nil
            Logger.account.error("Merging the anonymous account was rejected: \(error.localizedDescription)")
        } catch {
            // ja: この iPhone の端末情報の移行が完了していません。アプリを開き直すと再試行します
            appleSignInError = String(localized: "Moving this iPhone to your Apple account isn't finished yet. It retries when you reopen the app.")
            Logger.account.error("Merging the anonymous account failed: \(error.localizedDescription)")
        }
    }

    /// Apple のトークンを失効させる (App Store Review Guideline 5.1.1 (v) の Sign in with Apple を使うアカウントの削除)。
    /// 失効に使う authorization code は発行から 5 分しか使えないため、削除のたびに Sign in with Apple をやり直して受け取る。
    /// 交換と失効は Firebase Auth の Apple プロバイダに設定した Team ID / Key ID / 秘密鍵で Firebase が行う
    private func revokeAppleToken() async throws {
        // Firebase の revokeToken はサインイン中のユーザーが居ないと完了を呼ばずに終わる (async 版が戻らない) ため、先に確かめる
        guard Auth.auth().currentUser != nil else { throw AlarmifyAPIError.notSignedIn }
        let appleIDCredential = try await AppleIDAuthorization().perform()
        guard let authorizationCode = appleIDCredential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw AppleSignInError.missingAuthorizationCode
        }
        try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
    }

    /// Firebase Auth のユーザーに Apple の認証情報がリンクされているか
    private static func hasAppleID(user: User) -> Bool {
        user.providerData.contains { $0.providerID == AuthProviderID.apple.rawValue }
    }

    /// Apple が推奨する nonce の作り方 (暗号論的な乱数を 32 バイト)。Firebase のドキュメントの Sign in with Apple の例と同じ長さにする
    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// リクエストに設定する nonce のハッシュ (SHA-256 の 16 進文字列)。Apple は受け取った値を identity token の nonce にそのまま入れる
    private static func sha256(nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 配送先の登録と RevenueCat の identity 連携を並行して行う。
    /// RevenueCat の応答を待つ間に配送先の登録 (サインインの完了前に届いていた FCM トークンの登録を含む) を遅らせない。
    /// サインインが済んだこのタイミングで、Extension や前回の起動が積んだ適用結果の報告も送る
    private func registerDeviceAndLinkPurchases(uid: String) async {
        let linking = Task { @MainActor [weak self] in
            await self?.linkPurchases(uid: uid)
        }
        await registerDeviceIfPossible()
        await flushAlarmApplyReports()
        await linking.value
    }

    /// 未送信の適用結果 (`AlarmApplyReportQueue`) をバックエンドへ送る。
    /// 送れた報告と、送り直しても受け付けられない報告 (開発者メニューの固定 id や保持期間を過ぎたアラーム、未登録の端末、再スケジュール前の登録への報告) はキューから消し、
    /// それ以外の失敗 (未サインイン・通信エラー・エンドポイントが無い古いデプロイの 404) は次の機会に送り直せるよう残す。
    /// 何度呼んでも未送信分を送るだけで冪等。1 件でも送れたら `alarmApplyReportsFlushedAt` を更新し、ホームが履歴を読み直す
    func flushAlarmApplyReports() async {
        let queue = AlarmApplyReportQueue.shared
        var sent = false
        for report in queue.pending {
            do {
                try await apiClient.reportAlarmApply(report)
                queue.remove(report)
                sent = true
            } catch let error as AlarmifyAPIError where error.rejectsAlarmApplyReport {
                queue.remove(report)
            } catch {
                Logger.push.error("Reporting alarm apply result failed: \(error.localizedDescription)")
                break
            }
        }
        if sent {
            alarmApplyReportsFlushedAt = .now
        }
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

    /// ペイウォールの購入・復元の直前に呼び、購入を始めてよい状態かを返す。
    /// 起動時の logIn が失敗したまま匿名 ID で購入すると、webhook に uid が載らずサーバーのプランが更新されないため、
    /// ここで結び付けをやり直し、できなければ購入を始めない。
    /// 接続先がエミュレータの間は購入・復元を許さない (匿名 ID で行った購入は、本番へ戻した起動の logIn で本番の uid にマージされ、
    /// その後のイベントが本番の Firestore を更新してしまうため)
    func purchaseLinkState() async -> PurchaseLinkState {
        guard settings.backend == .production else { return .emulatorBackend }
        guard let uid else { return .notLinked }
        await ProEntitlement.logIn(appUserID: uid)
        return ProEntitlement.isLoggedIn(as: uid) ? .linked : .notLinked
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
    /// サーバーの削除に失敗した場合はサインイン状態を変えずにエラーを投げる (削除できていないアカウントを画面から消さない)。
    /// Apple の認証情報がリンクされていれば、先に Apple のトークンを失効させる。失効できなければ削除に進まずエラーを投げる
    /// (失効させないまま Firebase のユーザーを消すと、失効させる手段が残らない)。ユーザーが Apple のシートを閉じた時も同じく中断する
    func deleteAccount() async throws {
        // スタブは Firebase Auth の実アカウントに触れないため、Apple のトークンも失効させない
        if appleIDLinked, !settings.stubAPIClient {
            do {
                try await revokeAppleToken()
            } catch where Self.isAccountAlreadyGone(error) {
                // 前回の削除がサーバーで成功して応答だけ失われた後の再試行。失効は削除より先に済ませているため、端末側の状態を揃える処理へ進む
            }
        }
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
        appleIDLinked = false
        // 削除したアカウントへの切り替えの後処理は、送っても意味が無いため残さない
        pendingAnonymousMergeIDToken = nil
        UserDefaults.standard.removeObject(forKey: .pendingPurchaseSyncAppUserID)
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
        return URLSessionAlarmifyAPIClient(
            backend: settings.backend,
            idToken: {
                guard let user = Auth.auth().currentUser else { return nil }
                return try await user.getIDToken()
            },
            appCheckToken: {
                do {
                    return try await AppCheck.appCheck().token(forcingRefresh: false).token
                } catch {
                    // 取得できなくてもリクエストは送る (サーバー側の監視のみ / 強制の設定で扱いが決まる)
                    Logger.appCheck.error("App Check token unavailable: \(error.localizedDescription)")
                    return nil
                }
            }
        )
    }
}

/// ボタンを介さずに Sign in with Apple のシートを出し、Apple の認証情報を async で受け取る 1 回分のリクエスト。
/// ASAuthorizationController は結果を delegate で返すため class にする。呼び出し側の `perform()` の await が
/// このインスタンスを保持し、インスタンスがコントローラーを保持するため、結果が届くまで解放されない
@MainActor
private final class AppleIDAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// 表示中のコントローラー。delegate の呼び出しが終わるまで保持する
    private var controller: ASAuthorizationController?
    /// `perform()` の呼び出し元へ結果を返す continuation
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Sign in with Apple のシートを出し、ユーザーが認証するかシートを閉じるまで待つ
    func perform() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // トークンの失効に使う authorization code だけが要るため、メールアドレスと氏名は要求しない
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    /// Apple ID 以外の認証情報 (パスワード等) は要求していないため届かないが、届いた時も continuation を再開して呼び出し元を待たせない
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(result: .success(appleIDCredential))
        } else {
            finish(result: .failure(AppleSignInError.missingAuthorizationCode))
        }
    }

    /// シートを閉じた時は ASAuthorizationError.canceled が届き、呼び出し元が削除の中断として扱う
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(result: .failure(error))
    }

    /// シートを出す先。前面のウィンドウを使う
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = windowScenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        // 設定画面の操作から呼ぶため、画面を持つシーンは必ずある
        guard let windowScene = windowScenes.first else { preconditionFailure("No window scene to present Sign in with Apple") }
        return ASPresentationAnchor(windowScene: windowScene)
    }

    /// continuation は 1 度しか再開できないため、取り出してから再開する
    private func finish(result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

/// 未完了の匿名アカウントの統合に使う ID トークンの保存先 (keychain)。
/// ID トークンは有効期間 (1 時間) の間は匿名アカウントへのアクセス権になるため、UserDefaults ではなく keychain に置き、この端末からだけ読めるようにする
enum PendingAnonymousMergeIDTokenStore {
    /// keychain の項目を識別する kSecAttrService。bundle id を接頭辞にして他の項目と衝突させない
    static let service = "com.bannzai.Alarmify.pendingAnonymousMergeIDToken"

    /// 保存済みの ID トークン。無い・読めない時は nil
    static func load() -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// ID トークンを保存する。nil なら消す。既存の項目を消してから追加するため、何度呼んでも最後の値だけが残る
    static func save(_ idToken: String?) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let idToken else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(idToken.utf8)
        // 起動直後の前面復帰 (ロック解除後) で読めればよく、バックアップや他の端末へ移す必要は無い
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.account.error("Saving the pending anonymous merge token failed: \(status)")
        }
    }
}
