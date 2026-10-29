import SwiftUI

/// API トークンの一覧・発行・失効を行う画面。構成と文言は design_handoff/screens/api-tokens.md。
/// トークンごとの今月の件数はバックエンドの集計が無いため出さず、発行日だけを出す
struct APITokenView: View {
    @State private var session = AccountSession.shared
    @State private var model = APITokenModel()
    /// 失効の確認ダイアログを出しているトークン。nil の間はダイアログを出さない
    @State private var revokingToken: APIToken?

    /// トークンカードのチップから開く連携レシピ (design_handoff/screens/api-tokens.md「Recipes」)
    private static let featuredRecipes: [IntegrationRecipe] = [.githubActions, .homeAssistant, .shortcuts]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let issued = model.issued {
                    issuedCard(issued)
                        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                        .padding(.top, 8)
                }

                // ja: トークン
                SectionHeader(Text("Tokens"))
                VStack(spacing: 12) {
                    if model.tokens.isEmpty {
                        // ja: トークンはまだありません
                        Text("No tokens yet")
                            .font(.body)
                            .foregroundStyle(Color.paperTertiary)
                            .rowPadding()
                            .card()
                            .accessibilityIdentifier("api_token_empty")
                    }
                    ForEach(model.tokens) { token in
                        tokenCard(token)
                    }
                }
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)

                Button {
                    Task { await model.issue() }
                } label: {
                    // ja: トークンを発行
                    Text("Issue a token")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.loading)
                .accessibilityIdentifier("api_token_issue")
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .padding(.top, 20)
                if !ProEntitlement.isPro {
                    // ja: 無料プランはトークン 1 つと月 50 回のアラームまで
                    Text("The free plan includes one token and 50 alarms a month")
                        .font(.footnote)
                        .foregroundStyle(Color.paperTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 12)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 16)
                        .accessibilityIdentifier("api_token_error")
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        // ja: API トークン
        .navigationTitle(Text("API tokens"))
        .navigationBarTitleDisplayMode(.inline)
        // サインイン完了前に開いた場合や前面復帰でサインインし直した場合に、一覧を読み直す
        .task(id: session.uid) { await model.load() }
        .refreshable { await model.load() }
        // 無料プランの上限で発行を拒否された時のペイウォール。購入後のプランの反映は RevenueCat の webhook がサーバー側で行う
        .sheet(item: $model.paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
        }
        .confirmationDialog(
            // ja: このトークンを失効させますか?
            Text("Revoke this token?"),
            isPresented: Binding(
                get: { revokingToken != nil },
                set: { if !$0 { revokingToken = nil } }
            ),
            titleVisibility: .visible,
            presenting: revokingToken
        ) { token in
            Button(role: .destructive) {
                Task { await model.revoke(id: token.id) }
            } label: {
                // ja: 失効
                Text("Revoke")
            }
            .accessibilityIdentifier("api_token_revoke_confirm")
            Button(role: .cancel) {
            } label: {
                // ja: キャンセル
                Text("Cancel")
            }
        } message: { _ in
            // ja: このトークンを使っているサービスからの登録は届かなくなります。取り消せません。
            Text("Requests from services using this token will stop arriving. This cannot be undone.")
        }
    }

    /// 発行直後だけ出す平文のカード
    private func issuedCard(_ issued: IssuedAPIToken) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // ja: 新しいトークン
                Text("New token").eyebrowStyle()
                Spacer()
                // ja: 表示は今だけ
                Text("Shown only once")
                    .font(.footnote)
                    .foregroundStyle(Color.paperTertiary)
            }
            Text(verbatim: issued.secret)
                .font(.subheadline.monospaced())
                .foregroundStyle(Color.paper)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("api_token_secret")
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = issued.secret
                } label: {
                    // ja: トークンをコピー
                    Label("Copy token", systemImage: "doc.on.doc")
                }
                .buttonStyle(PrimaryButtonStyle(height: DesignMetrics.smallButtonHeight))
                .accessibilityIdentifier("api_token_copy")
                Button {
                    model.dismissIssued()
                } label: {
                    // ja: 完了
                    Text("Done")
                }
                .buttonStyle(SecondaryButtonStyle(height: DesignMetrics.smallButtonHeight, expands: false))
                .accessibilityIdentifier("api_token_dismiss_issued")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: .signalLine)
    }

    /// トークン 1 件のカード。平文は発行直後のものにしか無いため、それ以外の curl とレシピは prefix + 省略記号で埋める
    private func tokenCard(_ token: APIToken) -> some View {
        let secret = model.issued?.token.id == token.id ? model.issued?.secret : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: token.prefix)
                        .font(.body.monospaced())
                        .foregroundStyle(Color.paper)
                        // 識別子はカードではなく prefix に付ける (コンテナに付けると中のボタンの識別子を上書きしてしまう)
                        .accessibilityIdentifier("api_token_\(token.id)")
                    // ja: %@に発行
                    Text("Created \(token.createdAt, format: .dateTime.month(.abbreviated).day())")
                        .font(.footnote)
                        .foregroundStyle(Color.paperTertiary)
                }
                Spacer()
                Button {
                    revokingToken = token
                } label: {
                    // ja: 失効
                    Text("Revoke")
                        .font(.subheadline)
                        .foregroundStyle(Color.paperTertiary)
                }
                .buttonStyle(.plain)
                .disabled(model.loading)
                .accessibilityIdentifier("api_token_revoke_\(token.id)")
            }
            CurlExampleWithFireTime(
                curl: { curlExample(secret: secret, token: token, fireDate: $0) },
                copyIdentifier: "api_token_curl_copy_\(token.id)"
            )
            // チップは幅に収まらない分を次の行へ送る (名前を省略しない)
            FlowLayout(spacing: 8) {
                // ja: レシピ
                Text("Recipes")
                    .font(.subheadline)
                    .foregroundStyle(Color.paperTertiary)
                ForEach(Self.featuredRecipes) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe, apiToken: secret, backend: session.settings.backend)
                    } label: {
                        Chip(text: Text(verbatim: recipe.displayName), filled: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("api_token_recipe_\(recipe.rawValue)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// トークンカードの curl の例。平文が無いトークンは prefix + 省略記号で埋める
    /// - Parameter fireDate: 例に埋め込むアラームの発火日時。画面に併記する発火時刻と同じ値を渡す
    private func curlExample(secret: String?, token: APIToken, fireDate: Date) -> String {
        APITokenUsageExample.curl(secret: secret ?? token.prefix + "…", backend: session.settings.backend, fireDate: fireDate)
    }
}

/// curl の例と、その fire_at が端末の時刻でいつに当たるかの注記を並べたブロック。
/// 例・注記・コピーの値が同じ発火日時を指すよう、発火日時は 1 度だけ求めて両方に渡す
struct CurlExampleWithFireTime: View {
    /// 発火日時を受け取り、それを fire_at に埋め込んだ curl の例を返す
    let curl: (Date) -> String
    /// コピーボタンの accessibilityIdentifier
    let copyIdentifier: String

    var body: some View {
        // 注記が秒まで表示するため、秒が変わるたびに例と注記を作り直す。例の fire_at が過去日時にならないようにする意味もある
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fireDate = context.date.addingTimeInterval(APITokenUsageExample.fireDelay)
            VStack(spacing: 8) {
                // コピーは表示中の例をそのまま使い、注記の時刻と揃える
                CodeBlock(code: curl(fireDate), copyIdentifier: copyIdentifier)
                CurlExampleFireTimeNote(fireDate: fireDate)
            }
        }
    }
}

/// curl の例の fire_at (UTC) が、この端末のタイムゾーンで何日の何時に当たるかの注記。
/// fire_at は `Z` 付きの UTC で書くため、例だけでは端末の時刻でいつ鳴るかが読み取れない
struct CurlExampleFireTimeNote: View {
    /// curl の例に埋め込んだ発火日時
    let fireDate: Date

    var body: some View {
        // ja: この例はこの iPhone の時刻で%@に鳴ります。fire_at は UTC (Z) で指定します。
        Text("This example rings at \(fireDate, format: .dateTime.month(.defaultDigits).day().hour().minute(.twoDigits).second(.twoDigits).timeZone(.specificName(.short))) on this iPhone. fire_at is in UTC (Z).")
            .font(.footnote)
            .foregroundStyle(Color.paperTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("curl_example_fire_time")
    }
}

#Preview {
    NavigationStack {
        APITokenView()
    }
}
