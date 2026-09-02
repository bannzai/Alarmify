import SwiftUI

/// 連携レシピ画面。docs/recipes/ と同じ手順とスニペットを表示し、API トークンを埋め込んだ状態でコピーできる。
/// apiToken が nil (未発行) の間はプレースホルダを埋め込んで表示する
struct RecipesView: View {
    let apiToken: String?
    /// スニペットのエンドポイントに使う接続先
    let backend: AlarmifyBackend

    var body: some View {
        List {
            Section {
                ForEach(IntegrationRecipe.allCases) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe, apiToken: apiToken, backend: backend)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: recipe.displayName)
                            recipe.summary
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("recipe_\(recipe.rawValue)")
                }
            } footer: {
                if apiToken == nil {
                    // ja: API トークンを発行すると、スニペットにトークンが埋め込まれた状態で表示されます
                    Text("Issue an API token to see these snippets with your token filled in.")
                }
            }

            Section {
                Link(destination: URL(string: "https://bannzai.github.io/Alarmify/api")!) {
                    // ja: API リファレンス
                    Label("API reference", systemImage: "book")
                }
            }
        }
        // ja: 連携レシピ
        .navigationTitle("Integration recipes")
    }
}

/// レシピ 1 件の手順とスニペット
struct RecipeDetailView: View {
    let recipe: IntegrationRecipe
    let apiToken: String?
    let backend: AlarmifyBackend

    var body: some View {
        List {
            Section {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        step
                    }
                }
            } header: {
                // ja: 手順
                Text("Steps")
            }

            ForEach(Array(recipe.snippets(apiToken: apiToken, backend: backend).enumerated()), id: \.element.id) { index, snippet in
                Section {
                    ScrollView(.horizontal) {
                        Text(verbatim: snippet.body)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = snippet.body
                    } label: {
                        // ja: コピー
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("recipe_copy_\(recipe.rawValue)_\(index)")
                } header: {
                    Text(verbatim: snippet.label)
                }
            }

            Section {
                Link(destination: recipe.documentationURL) {
                    // ja: Web でこのレシピを見る
                    Label("Open this recipe on the web", systemImage: "safari")
                }
            }
        }
        .navigationTitle(Text(verbatim: recipe.displayName))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension IntegrationRecipe {
    /// 連携先の名称 (固有名詞のため翻訳しない)
    var displayName: String {
        switch self {
        case .shell: "cron / shell"
        case .githubActions: "GitHub Actions"
        case .homeAssistant: "Home Assistant"
        case .shortcuts: "Shortcuts"
        case .grafana: "Grafana"
        case .uptimeKuma: "Uptime Kuma"
        }
    }

    var summary: Text {
        switch self {
        case .shell:
            // ja: スクリプト・crontab・CI から 1 行の curl で鳴らす
            Text("One curl line for scripts, crontab and CI jobs")
        case .githubActions:
            // ja: workflow の完了・失敗時に鳴らす
            Text("Ring when a workflow finishes or fails")
        case .homeAssistant:
            // ja: 任意のオートメーションから呼べる rest_command
            Text("A rest_command you can call from any automation")
        case .shortcuts:
            // ja: 「URL の内容を取得」アクションで鳴らす
            Text("The 'Get Contents of URL' action, for Shortcuts automations")
        case .grafana:
            // ja: アラートの発火時に鳴らす Webhook 通知先
            Text("A webhook contact point that rings when an alert fires")
        case .uptimeKuma:
            // ja: モニターがダウンした時に鳴らす Webhook 通知
            Text("A webhook notification that rings when a monitor goes down")
        }
    }

    var steps: [Text] {
        switch self {
        case .shell:
            [
                // ja: スクリプトの末尾や crontab に curl を置きます。`fire_in` は受信からの秒数なので日時の計算は不要です
                Text("Put the curl call at the end of a script or in a crontab. 'fire_in' counts seconds from the request, so no date arithmetic is needed."),
                // ja: トークンは環境変数 `ALARMIFY_TOKEN` に置き、コミットするファイルに書かないようにします
                Text("Keep the token in the 'ALARMIFY_TOKEN' environment variable rather than in a file you commit."),
                // ja: 失敗時だけ鳴らす時は終了ステータスを変数に取り、アラーム送信後にその値で exit します (CI が失敗を検知できるように)
                Text("To ring only when a command fails, keep its exit status in a variable and exit with it after sending the alarm, so CI still sees the failure."),
            ]
        case .githubActions:
            [
                // ja: トークンをリポジトリの secret `ALARMIFY_TOKEN` に登録します。`gh secret set` はプロンプトでトークンを貼り付けるため、シェルの履歴に残りません
                Text("Store the token as the repository secret 'ALARMIFY_TOKEN'. 'gh secret set' prompts for the value, so the token stays out of your shell history."),
                // ja: workflow の末尾にステップを追加します。`if: always()` で失敗時にも鳴り、`if: failure()` なら失敗時だけ鳴ります
                Text("Add the step at the end of the job. 'if: always()' also rings after a failure; 'if: failure()' rings only when something broke."),
            ]
        case .homeAssistant:
            [
                // ja: `secrets.yaml` に Authorization ヘッダーの値を置きます
                Text("Put the Authorization header value in 'secrets.yaml'."),
                // ja: `configuration.yaml` に rest_command を定義し、Home Assistant を再起動します
                Text("Define the rest_command in 'configuration.yaml' and restart Home Assistant."),
                // ja: オートメーションの actions から `rest_command.alarmify_alarm` を `fire_in` と `title` 付きで呼びます
                Text("Call 'rest_command.alarmify_alarm' from an automation's actions with 'fire_in' and 'title'."),
            ]
        case .shortcuts:
            [
                // ja: 「URL の内容を取得」アクションを追加し、URL を設定します
                Text("Add the 'Get Contents of URL' action and set the URL."),
                // ja: メソッドを POST にし、ヘッダーに Authorization と Content-Type を追加します
                Text("Set Method to POST and add the Authorization and Content-Type headers."),
                // ja: 要求本文を JSON にし、`fire_in` (数値) と `title` (テキスト) を追加します
                Text("Set Request Body to JSON and add 'fire_in' (Number) and 'title' (Text)."),
            ]
        case .grafana:
            [
                // ja: Alerting > Contact points で Webhook の通知先を追加し、URL と HTTP Method (POST) を設定します
                Text("Alerting > Contact points: add a Webhook contact point with the URL and HTTP Method POST."),
                // ja: Authentication Header Scheme を Bearer にし、Credentials にトークンを貼り付けます
                Text("Set Authentication Header Scheme to Bearer and paste the token into Credentials."),
                // ja: Optional Webhook settings で Custom Payload を有効にし、テンプレートを貼り付けます
                Text("Under Optional Webhook settings, enable Custom Payload and paste the template."),
                // ja: 解決時にも鳴らないよう、Disable resolved message をオンにします
                Text("Turn on Disable resolved message so a resolved alert does not ring again."),
                // ja: 通知先の Test で、1 分以内に iPhone が鳴ることを確認します
                Text("Use Test on the contact point; your iPhone should ring within a minute."),
            ]
        case .uptimeKuma:
            [
                // ja: Settings > Notifications で Webhook 通知を追加し、Post URL を設定します
                Text("Settings > Notifications: add a Webhook notification with the Post URL."),
                // ja: Request Body を Custom Body にしてテンプレートを貼り付け、Additional Headers にトークンを貼り付けます
                Text("Set Request Body to Custom Body, paste the template, and paste the headers into Additional Headers."),
                // ja: 鳴らしたいモニターで通知を有効にし、Test で確認します。UP でも鳴ります (タイトルが "is up" になります)
                Text("Enable the notification on the monitors that should wake you, then press Test. UP events ring too, with an 'is up' title."),
            ]
        }
    }
}

#Preview("Recipes") {
    NavigationStack {
        RecipesView(apiToken: "alm_example_token", backend: .production)
    }
}

#Preview("GitHub Actions") {
    NavigationStack {
        RecipeDetailView(recipe: .githubActions, apiToken: "alm_example_token", backend: .production)
    }
}
