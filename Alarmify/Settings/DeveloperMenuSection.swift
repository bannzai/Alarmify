#if DEBUG
import SwiftUI

/// 開発者メニュー。動作確認で到達しづらい状態を作る操作を置く (.claude/rules/debug-menu-for-verification.md)。
/// 接続先がローカルの Firebase Emulator のため DEBUG ビルドにだけ含める。
/// 開発者にしか表示されないため、文言は `Text(verbatim:)` で翻訳対象から外す
struct DeveloperMenuSection: View {
    @Binding var credential: AccountCredential?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button {
                Task { await createAnonymousAccount() }
            } label: {
                Text(verbatim: "Create an anonymous account for verification")
            }
            .accessibilityIdentifier("debug_create_anonymous_account")
            .disabled(credential != nil)

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(verbatim: "Developer menu")
        } footer: {
            Text(verbatim: "Connects to the local Firebase Emulator (npm --prefix functions run serve).")
        }
    }

    /// 冪等: 既にアカウントがある場合は作り直さず、そのままにする
    private func createAnonymousAccount() async {
        guard credential == nil else { return }
        do {
            let created = try await EmulatorAccountFactory.signUpAnonymously()
            try AccountStore.save(created)
            credential = created
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
