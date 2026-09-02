import SwiftUI

/// API トークンの一覧・発行・失効を行う画面。デザイン受領前の仮 UI
struct APITokenView: View {
    @State private var model = APITokenModel()

    var body: some View {
        List {
            if let issued = model.issued, let curlExample = model.curlExample {
                Section {
                    Text(issued.secret)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("api_token_secret")
                    Button {
                        UIPasteboard.general.string = issued.secret
                    } label: {
                        // ja: トークンをコピーする
                        Text("Copy token")
                    }
                    .accessibilityIdentifier("api_token_copy")
                    Text(curlExample)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("api_token_curl")
                    Button {
                        UIPasteboard.general.string = curlExample
                    } label: {
                        // ja: curl の例をコピーする
                        Text("Copy curl example")
                    }
                    Button {
                        model.dismissIssued()
                    } label: {
                        // ja: 閉じる
                        Text("Close")
                    }
                } header: {
                    // ja: 発行したトークン
                    Text("Issued token")
                } footer: {
                    // ja: この値を見られるのは今だけです。外部サービスに設定してから閉じてください。
                    Text("This value is shown only once. Save it into your service before closing.")
                }
            }

            Section {
                if model.tokens.isEmpty {
                    // ja: トークンはまだありません
                    Text("No tokens yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.tokens) { token in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(token.prefix)
                            .font(.body.monospaced())
                        Text(token.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await model.revoke(id: token.id) }
                        } label: {
                            // ja: 失効させる
                            Text("Revoke")
                        }
                    }
                }
            } header: {
                // ja: 発行済みのトークン
                Text("Tokens")
            }

            Section {
                Button {
                    Task { await model.issue() }
                } label: {
                    // ja: トークンを発行する
                    Text("Issue a token")
                }
                .disabled(model.loading)
                .accessibilityIdentifier("api_token_issue")
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("api_token_error")
                } header: {
                    // ja: エラー
                    Text("Error")
                }
            }
        }
        // ja: API トークン
        .navigationTitle(Text("API tokens"))
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

#Preview {
    NavigationStack {
        APITokenView()
    }
}
