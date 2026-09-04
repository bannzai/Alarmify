import FirebaseAppCheck
import FirebaseCore

/// App Check のプロバイダを実行環境で分ける。
/// simulator には App Attest (DCAppAttestService) が無いためデバッグプロバイダを使い、実機は App Attest で端末を証明する。
///
/// デバッグプロバイダのトークンは、環境変数 `AppCheckDebugToken` (旧名 `FIRAAppCheckDebugToken`) で渡すか、
/// 渡さない場合に SDK が生成してコンソールへ出す UUID (`Firebase App Check Debug Token: '...'`) を
/// Firebase コンソールの App Check へ登録して使う。トークン自体はソース・リポジトリに置かない (漏れると誰でも検証を通せるため)。
///
/// App Store / TestFlight 配布のバイナリは simulator 向けにビルドされないため、この分岐でデバッグプロバイダが本番に載ることはない。
final class AlarmifyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        // App Attest を使えない端末・OS では nil が返る。その場合 App Check のトークンは取得できず、
        // リクエストはトークン無しで送られる (サーバー側が監視のみのモードの間は通る)
        return AppAttestProvider(app: app)
        #endif
    }
}
