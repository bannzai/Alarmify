import AlarmKit
import SwiftUI
import UserNotifications

extension String {
    /// オンボーディングを完了 (最後まで進んだ・スキップした) したかを保存する UserDefaults キー。
    /// false の間は起動時にオンボーディングを表示する (AlarmifyApp)
    static let onboardingCompleted = "onboardingCompleted"
}

/// 初回起動のオンボーディング (5 画面)。設計の根拠と確定コピーは design_handoff/onboarding-rationale.md、
/// 画面ごとの構成は design_handoff/screens/onboarding.md。
/// 権限の要求・トークンの発行・テストアラームの登録は通常利用と同じ関数を呼び、専用の経路を作らない
struct OnboardingView: View {
    /// 画面の順序。コンセプトは「Step n of 4」に数えない
    private enum Step: Int, CaseIterable {
        case concept
        case alarms
        case push
        case token
        case test
    }

    @AppStorage(.onboardingCompleted) private var onboardingCompleted = false
    @State private var step: Step = .concept
    @State private var session = AccountSession.shared
    @State private var tokenModel = APITokenModel()
    @State private var alarmAuthorization = AlarmKitScheduler.authorizationState
    /// 登録したテストアラームの発火日時。登録後はカードの数字をカウントダウンに切り替える
    @State private var testAlarmFireDate: Date?
    /// 権限の要求・テストアラームの登録に失敗した時のエラー。文言はそのまま表示する
    @State private var errorMessage: String?
    /// トークンの発行が進行中かどうか。`APITokenModel.loading` は一覧の再取得も含むため、この画面の発行手順全体を 1 つの状態で持つ
    @State private var tokenPreparing = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressSegments(total: Step.allCases.count, filled: step.rawValue + 1)
                .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                .frame(height: 44)
            VStack(alignment: .leading, spacing: 0) {
                heading
                    .padding(.horizontal, DesignMetrics.heroHorizontalPadding)
                    .padding(.top, 28)
                Spacer(minLength: 16)
                visual
                    .padding(.horizontal, DesignMetrics.heroHorizontalPadding)
                Spacer(minLength: 16)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.heroHorizontalPadding)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("onboarding_error")
                }
                buttons
                    .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                    .padding(.bottom, 8)
            }
            .id(step)
            .transition(.opacity)
        }
        .screenBackground()
        .animation(.easeInOut(duration: 0.2), value: step)
        .accessibilityIdentifier("onboarding_step_\(step.rawValue)")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // OS の設定アプリで権限を変えて戻ってきた時に、テストアラームの画面のボタンを切り替える
            alarmAuthorization = AlarmKitScheduler.authorizationState
        }
    }

    // MARK: - 見出し

    @ViewBuilder
    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case .concept:
                // 製品名。翻訳対象ではないため verbatim
                Text(verbatim: "Signalarm").eyebrowStyle()
                // ja: どんな Webhook も本物のアラームに
                Text("Turn any webhook into a real alarm")
                    .font(.largeTitle.bold())
                // ja: サービスから HTTP リクエストを 1 つ送るだけで、この iPhone が鳴ります。通知ではなくアラームなので、サイレントモードや集中モードでも、アプリを閉じていても鳴ります。
                lead(Text("Send one HTTP request from your service and this iPhone rings. Not a notification but an alarm that cuts through Silent mode and Focus even when the app is closed."))
            case .alarms:
                stepEyebrow(1)
                // ja: アラームを許可
                Text("Allow alarms")
                    .font(.largeTitle.bold())
                // ja: Signalarm は標準の時計と同じ AlarmKit で鳴ります。この許可が無いと何も鳴りません。
                lead(Text("Signalarm rings through AlarmKit, the same system as the built-in Clock. Nothing can ring without this permission."))
            case .push:
                stepEyebrow(2)
                // ja: 通知を許可
                Text("Allow notifications")
                    .font(.largeTitle.bold())
                // ja: サービスからの依頼は push でこの iPhone に届きます。アプリを閉じている間もアラームの依頼を受け取れます。
                lead(Text("Your services reach this iPhone through push. That is how an alarm request arrives while the app is closed."))
            case .token:
                stepEyebrow(3)
                // ja: 最初の API トークン
                Text("Your first API token")
                    .font(.largeTitle.bold())
                // ja: 鳴らしたいサービスに貼り付けてください。表示されるのは今だけです。
                lead(Text("Paste it into the service that should wake you. It is shown only once."))
            case .test:
                stepEyebrow(4)
                // ja: 鳴らしてみる
                Text("Hear it ring")
                    .font(.largeTitle.bold())
                // ja: 1 分後にテストアラームを登録します。iPhone をロックして待ってください。サービスからの本番の依頼も同じように鳴ります。
                lead(Text("Schedule a test alarm one minute from now. Lock the iPhone and wait. Real requests from your services work the same way."))
            }
        }
        .foregroundStyle(Color.paper)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 権限・トークン・テストの 4 画面に付ける「Step n of 4」。コンセプトの画面は数えない
    private func stepEyebrow(_ index: Int) -> some View {
        // ja: ステップ %lld / %lld
        Text("Step \(index) of \(Step.allCases.count - 1)").eyebrowStyle()
    }

    private func lead(_ text: Text) -> some View {
        text
            .font(.body)
            .foregroundStyle(Color.paperSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 中央のビジュアル

    @ViewBuilder
    private var visual: some View {
        switch step {
        case .concept:
            conceptFlow
        case .alarms:
            permissionCard(
                systemImage: "bell",
                // ja: アラームにできること
                title: Text("What alarms can do"),
                lines: [
                    // ja: サイレントモードと集中モードでも鳴る
                    Text("Ring in Silent mode and every Focus"),
                    // ja: ロック画面に全画面で表示
                    Text("Show full screen on the Lock Screen"),
                    // ja: 止めるまで鳴り続ける
                    Text("Keep ringing until you stop them"),
                ]
            )
        case .push:
            permissionCard(
                systemImage: "iphone",
                // ja: push の用途
                title: Text("What push is used for"),
                lines: [
                    // ja: サービスからのアラーム依頼を届ける
                    Text("Deliver alarm requests from your services"),
                    // ja: バックグラウンドでアラームを登録する
                    Text("Schedule the alarm in the background"),
                    // ja: 宣伝や無関係なバナーは送らない
                    Text("No marketing and no unrelated banners"),
                ]
            )
        case .token:
            tokenVisual
        case .test:
            testAlarmCard
        }
    }

    /// コンセプト画面の 3 段のフロー。3 段目 (この iPhone が鳴る) だけ枠とアイコンを橙にする
    private var conceptFlow: some View {
        VStack(spacing: 0) {
            flowNode(
                systemImage: "server.rack",
                // ja: あなたのサービス
                title: Text("Your service"),
                // 連携先の名前 (固有名詞) の列挙。翻訳しない
                subtitle: Text(verbatim: "GitHub Actions · Home Assistant · cron"),
                highlighted: false
            )
            flowConnector
            flowNode(
                systemImage: "terminal",
                // 製品名 + API。翻訳しない
                title: Text(verbatim: "Signalarm API"),
                subtitle: Text(verbatim: "POST /v1/alarms"),
                monospacedSubtitle: true,
                highlighted: false
            )
            flowConnector
            flowNode(
                systemImage: "bell",
                // ja: この iPhone が鳴る
                title: Text("This iPhone rings"),
                // ja: ロック画面に AlarmKit のアラーム
                subtitle: Text("AlarmKit alarm on the Lock Screen"),
                highlighted: true
            )
        }
    }

    private var flowConnector: some View {
        Rectangle()
            .fill(Color.signalLine)
            .frame(width: 1, height: 28)
    }

    /// フローの 1 段。`monospacedSubtitle` はエンドポイント (`POST /v1/alarms`) のように等幅で見せる補足に付ける
    private func flowNode(systemImage: String, title: Text, subtitle: Text, monospacedSubtitle: Bool = false, highlighted: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(highlighted ? Color.signal : Color.paperSecondary)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.headline)
                    .foregroundStyle(Color.paper)
                subtitle
                    .font(monospacedSubtitle ? .footnote.monospaced() : .footnote)
                    .foregroundStyle(Color.paperTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(border: highlighted ? .signalLine : .hairline)
    }

    /// 権限画面のカード。何ができる権限かを 3 行で示す (pre-permission)
    private func permissionCard(systemImage: String, title: Text, lines: [Text]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.signalText)
                    .frame(width: 40, height: 40)
                    .background(Color.signalSoft, in: RoundedRectangle(cornerRadius: DesignMetrics.smallButtonCornerRadius, style: .continuous))
                title
                    .font(.headline)
                    .foregroundStyle(Color.paper)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.signal)
                        line
                            .font(.subheadline)
                            .foregroundStyle(Color.paperSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: DesignMetrics.featureCardCornerRadius)
    }

    /// トークン画面のカードと curl。発行中はカードの位置に ProgressView、失敗時はエラー文と再試行ボタンを出す
    @ViewBuilder
    private var tokenVisual: some View {
        if let issued = tokenModel.issued, let curlExample = tokenModel.curlExample {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    // ja: トークン
                    Text("Token").eyebrowStyle(color: .paperTertiary)
                    Text(verbatim: issued.secret)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Color.paper)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding_token_secret")
                    HStack {
                        // ja: 表示は今だけ
                        Text("Shown only once")
                            .font(.footnote)
                            .foregroundStyle(Color.paperTertiary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = issued.secret
                        } label: {
                            // ja: コピー
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(SoftAccentButtonStyle())
                        .accessibilityIdentifier("onboarding_token_copy")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(border: .signalLine)
                CodeBlock(code: curlExample, copyIdentifier: "onboarding_curl_copy")
            }
        } else if tokenPreparing {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 16) {
                if let errorMessage = tokenModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("onboarding_token_error")
                }
                Button {
                    Task { await prepareToken() }
                } label: {
                    // ja: もう一度発行する
                    Text("Try issuing again")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("onboarding_token_retry")
            }
            .padding(16)
            .card()
        }
    }

    /// テストアラームのカード。登録前は 01:00、登録後は発火までのカウントダウンを出す
    private var testAlarmCard: some View {
        VStack(spacing: 10) {
            // ja: テストアラーム
            Text("Test alarm").eyebrowStyle(color: .paperTertiary)
            Group {
                if let testAlarmFireDate {
                    Text(testAlarmFireDate, style: .timer)
                } else {
                    // 登録前の見本の数字 (1 分)。翻訳しない
                    Text(verbatim: "01:00")
                }
            }
            .font(.clockDigits)
            .monospacedDigit()
            .foregroundStyle(Color.signalText)
            .accessibilityIdentifier("onboarding_test_alarm_time")
            // ja: iPhone をロックすると鳴ります
            Text("rings after you lock the iPhone")
                .font(.subheadline)
                .foregroundStyle(Color.paperTertiary)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: DesignMetrics.featureCardCornerRadius)
    }

    // MARK: - ボタン

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 4) {
            switch step {
            case .concept:
                Button {
                    advance(to: .alarms)
                } label: {
                    // ja: はじめる
                    Text("Get started")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding_get_started")
                // 副ボタンが無い画面でも下の余白 (テキストボタンの高さ) を揃える
                Color.clear.frame(height: DesignMetrics.textButtonHeight)
            case .alarms:
                Button {
                    Task { await requestAlarmAuthorization(then: .push) }
                } label: {
                    // ja: アラームを許可
                    Text("Allow alarms")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding_allow_alarms")
                notNowButton(next: .push)
            case .push:
                Button {
                    Task { await requestNotificationAuthorization() }
                } label: {
                    // ja: 通知を許可
                    Text("Allow notifications")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding_allow_notifications")
                notNowButton(next: .token)
            case .token:
                Button {
                    advance(to: .test)
                } label: {
                    // ja: 次へ
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(tokenPreparing)
                .accessibilityIdentifier("onboarding_continue")
                if tokenModel.issued == nil {
                    Button {
                        advance(to: .test)
                    } label: {
                        // ja: あとで発行する
                        Text("Issue a token later")
                    }
                    .buttonStyle(TextButtonStyle())
                    .disabled(tokenPreparing)
                    .accessibilityIdentifier("onboarding_issue_later")
                } else {
                    Color.clear.frame(height: DesignMetrics.textButtonHeight)
                }
            case .test:
                if alarmAuthorization != .authorized {
                    Button {
                        Task { await requestAlarmAuthorization(then: nil) }
                    } label: {
                        // ja: アラームを許可
                        Text("Allow alarms")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding_allow_alarms")
                } else if testAlarmFireDate == nil {
                    Button {
                        Task { await scheduleTestAlarm() }
                    } label: {
                        // ja: 1 分後にテストアラームを鳴らす
                        Label("Ring a test alarm in 1 minute", systemImage: "bell.and.waves.left.and.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding_ring_test")
                } else {
                    Button {
                        complete()
                    } label: {
                        // ja: ホームへ
                        Text("Go to home")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding_go_home")
                }
                if testAlarmFireDate == nil {
                    Button {
                        complete()
                    } label: {
                        // ja: スキップ
                        Text("Skip")
                    }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityIdentifier("onboarding_skip")
                } else {
                    Color.clear.frame(height: DesignMetrics.textButtonHeight)
                }
            }
        }
    }

    private func notNowButton(next: Step) -> some View {
        Button {
            advance(to: next)
        } label: {
            // ja: あとで
            Text("Not now")
        }
        .buttonStyle(TextButtonStyle())
        .accessibilityIdentifier("onboarding_not_now")
    }

    // MARK: - 操作

    private func advance(to next: Step) {
        errorMessage = nil
        step = next
        if next == .token {
            Task { await prepareToken() }
        }
    }

    private func complete() {
        onboardingCompleted = true
    }

    /// AlarmKit の権限を要求する。結果にかかわらず `next` へ進む (拒否時の再要求は設定 > Permissions から)。
    /// `next` が nil (テストアラームの画面からの要求) なら同じ画面に留まり、許可されればテストアラームのボタンに切り替わる
    private func requestAlarmAuthorization(then next: Step?) async {
        do {
            alarmAuthorization = try await AlarmKitScheduler.requestAuthorization()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        if let next {
            advance(to: next)
        }
    }

    /// 通知の権限を要求し、結果にかかわらず APNs へ登録して次へ進む
    /// (許可の有無に関わらずデバイストークンは取得できる。AppDelegate は起動時に登録だけを行い、権限の要求はここと設定に任せる)
    private func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        UIApplication.shared.registerForRemoteNotifications()
        advance(to: .token)
    }

    /// 最初のトークンを発行する。既にトークンがある (再オンボーディング) 場合は発行せず、この画面を飛ばす。
    /// 一覧の取得に失敗した (未サインイン等) 場合は発行を試みず、エラーと再試行ボタンを出す
    private func prepareToken() async {
        guard !tokenPreparing else { return }
        tokenPreparing = true
        defer { tokenPreparing = false }
        await tokenModel.load()
        guard tokenModel.errorMessage == nil else { return }
        guard tokenModel.tokens.isEmpty else {
            advance(to: .test)
            return
        }
        await tokenModel.issue()
    }

    private func scheduleTestAlarm() async {
        do {
            testAlarmFireDate = try await TestAlarm.schedule()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Concept") {
    OnboardingView()
}
