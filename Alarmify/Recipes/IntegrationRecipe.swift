import Foundation

/// 連携先ごとのセットアップ用スニペット。docs/recipes/ と同じ内容をアプリ内で表示し、API トークンを埋め込んだ状態でコピーできるようにする。
/// 表示名・手順の文言は View 側で持ち、ここには翻訳しない技術的な内容 (コマンド・設定ファイル・URL) だけを置く
enum IntegrationRecipe: String, CaseIterable, Identifiable {
    case shell
    case githubActions
    case homeAssistant
    case shortcuts
    case grafana
    case uptimeKuma

    /// コピー対象のスニペット 1 つ。label はファイル名や設定項目名などの翻訳しない識別子
    struct Snippet: Identifiable, Equatable {
        var label: String
        var body: String

        var id: String { label }
    }

    /// アラーム登録 API のエンドポイント。バックエンド (#2) が未実装のため、LP (docs/index.html) と同じ予定のホスト名
    static let endpoint = "https://api.alarmify.app/v1/alarms"
    /// API トークン未発行時にスニペットへ埋め込むプレースホルダ (docs/recipes/ と同じ表記)
    static let apiTokenPlaceholder = "<API_TOKEN>"
    /// スニペットのテンプレート内でトークンを差し込む位置
    private static let apiTokenMarker = "{{API_TOKEN}}"
    private static let documentationBaseURL = "https://bannzai.github.io/Alarmify/recipes/"

    var id: String { rawValue }

    /// docs/recipes/ の対応ページ
    var documentationURL: URL {
        let slug: String
        switch self {
        case .shell: slug = "cron"
        case .githubActions: slug = "github-actions"
        case .homeAssistant: slug = "home-assistant"
        case .shortcuts: slug = "shortcuts"
        case .grafana: slug = "grafana"
        case .uptimeKuma: slug = "uptime-kuma"
        }
        return URL(string: Self.documentationBaseURL + slug)!
    }

    /// トークンを埋め込んだスニペット。apiToken が nil (未発行) ならプレースホルダを埋め込む
    func snippets(apiToken: String?) -> [Snippet] {
        let token = apiToken ?? Self.apiTokenPlaceholder
        return templates.map { Snippet(label: $0.label, body: $0.body.replacingOccurrences(of: Self.apiTokenMarker, with: token)) }
    }

    private var templates: [Snippet] {
        let endpoint = Self.endpoint
        switch self {
        case .shell:
            return [
                Snippet(label: "curl", body: """
                curl -sS -X POST \(endpoint) \\
                  -H "Authorization: Bearer \(Self.apiTokenMarker)" \\
                  -H "Content-Type: application/json" \\
                  -d '{"fire_in":300,"title":"Backup finished"}'
                """),
                Snippet(label: "Ring only when a command fails", body: """
                export ALARMIFY_TOKEN="\(Self.apiTokenMarker)"
                ./deploy.sh; status=$?
                if [ "$status" -ne 0 ]; then
                  curl -sS -X POST \(endpoint) \\
                    -H "Authorization: Bearer $ALARMIFY_TOKEN" \\
                    -H "Content-Type: application/json" \\
                    -d '{"fire_in":0,"title":"Deploy failed"}'
                fi
                exit "$status"
                """),
            ]
        case .githubActions:
            return [
                Snippet(label: "gh secret set", body: """
                gh secret set ALARMIFY_TOKEN
                """),
                Snippet(label: "API token (paste at the prompt)", body: Self.apiTokenMarker),
                Snippet(label: ".github/workflows/deploy.yml", body: """
                      - name: Ring my iPhone
                        if: always()
                        env:
                          ALARMIFY_TOKEN: ${{ secrets.ALARMIFY_TOKEN }}
                        run: |
                          curl -sS -X POST \(endpoint) \\
                            -H "Authorization: Bearer $ALARMIFY_TOKEN" \\
                            -H "Content-Type: application/json" \\
                            -d "{\\"fire_in\\":0,\\"title\\":\\"${{ github.workflow }}: ${{ job.status }}\\"}"
                """),
            ]
        case .homeAssistant:
            return [
                Snippet(label: "secrets.yaml", body: """
                alarmify_authorization: "Bearer \(Self.apiTokenMarker)"
                """),
                Snippet(label: "configuration.yaml", body: """
                rest_command:
                  alarmify_alarm:
                    url: "\(endpoint)"
                    method: post
                    headers:
                      authorization: !secret alarmify_authorization
                    content_type: "application/json"
                    payload: '{"fire_in": {{ fire_in | default(0) }}, "title": {{ title | default("Home Assistant") | to_json }}}'
                """),
                Snippet(label: "automations.yaml", body: """
                    - action: rest_command.alarmify_alarm
                      data:
                        fire_in: 0
                        title: "Front door opened"
                """),
            ]
        case .shortcuts:
            return [
                Snippet(label: "URL", body: endpoint),
                Snippet(label: "Header: Authorization", body: "Bearer \(Self.apiTokenMarker)"),
                Snippet(label: "Header: Content-Type", body: "application/json"),
                Snippet(label: "Request Body (JSON)", body: """
                {"fire_in": 300, "title": "Leave now"}
                """),
            ]
        case .grafana:
            return [
                Snippet(label: "URL", body: endpoint),
                Snippet(label: "Authentication Header Credentials", body: Self.apiTokenMarker),
                Snippet(label: "Custom Payload", body: """
                {{ coll.Dict "fire_in" 0 "title" (printf "%s: %s" (.Status | toUpper) .CommonLabels.alertname) | data.ToJSON }}
                """),
            ]
        case .uptimeKuma:
            return [
                Snippet(label: "Post URL", body: endpoint),
                Snippet(label: "Custom Body", body: """
                {% assign state = "down" %}{% if heartbeatJSON['status'] == 1 %}{% assign state = "up" %}{% endif %}
                {
                  "fire_in": 0,
                  "title": {{ monitorJSON['name'] | append: " is " | append: state | json }}
                }
                """),
                Snippet(label: "Additional Headers", body: """
                {
                  "Authorization": "Bearer \(Self.apiTokenMarker)",
                  "Content-Type": "application/json"
                }
                """),
            ]
        }
    }
}
