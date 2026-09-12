import AlarmKit
import SwiftUI

/// ホーム。次に鳴るアラームのカード、直近の履歴、連携 (API トークン・レシピ) への導線を出す。
/// 構成と文言は design_handoff/screens/home.md。技術検証用の情報 (権限状態・登録済みアラーム・デバイストークン) は開発者メニューにある
struct ContentView: View {
    @State private var session = AccountSession.shared
    @State private var alarms: [Alarm] = []
    @State private var errorMessage: String?
    /// バックエンドの履歴 (新しい順)。件数の上限はサーバーがプランで決める
    @State private var history: [AlarmHistoryEntry] = []
    /// 履歴の取得に失敗したエラーの説明。成功したら nil
    @State private var historyError: String?
    /// 履歴を読み込み中かどうか。初回の空表示と「履歴なし」を区別する
    @State private var historyLoading = false
    /// 発行済みの API トークン。履歴と次のアラームに送信元 (prefix) を出すことと、連携の行の件数に使う
    @State private var tokens: [APIToken] = []
    /// 表示中のペイウォールの文脈。履歴の続きを見る導線から開く
    @State private var paywallTrigger: PaywallTrigger?

    /// 履歴の取得件数。無料プランはサーバー側で直近数件に切り詰められ、Pro はこの件数まで返る (ホームに収まる量)
    private static let historyLimit = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nextAlarmCard
                        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                        .padding(.top, 4)
                    scheduledAlarmsRow
                        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                        .padding(.top, 12)

                    // ja: 直近のアラーム
                    SectionHeader(Text("Recent alarms")) {
                        Button {
                            Task { await scheduleTestAlarm() }
                        } label: {
                            // ja: テストを鳴らす
                            Text("Ring a test")
                        }
                        .buttonStyle(AccentTextButtonStyle())
                        .accessibilityIdentifier("home_ring_test")
                    }
                    historyCard
                        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)

                    // ja: 連携
                    SectionHeader(Text("Connect"))
                    connectCard
                        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.destructive)
                            .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                            .padding(.top, 16)
                            .accessibilityIdentifier("home_error")
                    }
                }
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Signalarm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        // ja: 設定
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("open_settings")
                }
            }
            .refreshable {
                refresh()
                await loadRemote()
            }
            // 起動直後はサインインの完了前に走って履歴を取れないため、uid が決まったらもう一度読む
            .task(id: session.uid) {
                refresh()
                await loadRemote()
            }
            .task {
                // push (Notification Service Extension / background push) や開発者メニューで登録・取消されたアラームと、発火による状態の変化を
                // 再読み込みを待たずに反映する。前面中に Extension が登録した時は、この app 本体しか報告を送れず前面復帰も起きないため、
                // ここで Extension が積んだ報告を送り、サーバー側に増えた履歴も読み直す
                for await alarms in AlarmKitScheduler.alarmUpdates {
                    self.alarms = alarms
                    await session.flushAlarmApplyReports()
                    await loadHistory()
                }
            }
            .onChange(of: session.alarmApplyReportsFlushedAt) {
                // この端末の反映結果がサーバーに届いたので、履歴の状態表示を読み直す
                Task { await loadHistory() }
            }
            .sheet(item: $paywallTrigger, onDismiss: {
                // Pro を購入・復元して閉じた時に、無料プランの 3 件のままの履歴を読み直す (サーバーのプランは RevenueCat の webhook で変わるため、
                // 反映が遅れていればこの読み直しではまだ 3 件で、次の再読み込みで増える)
                Task { await loadHistory() }
            }) { trigger in
                PaywallPage(trigger: trigger)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refresh()
                // 起動時のサインインが一過性のエラーで失敗していた場合、前面復帰のたびにやり直す。
                // サインインの中で未送信の適用結果も送られるため、その後に履歴を読み直す
                Task {
                    await session.signIn()
                    await loadRemote()
                }
            }
        }
        .tint(Color.signalText)
    }

    // MARK: - 次に鳴るアラーム

    /// 発火時刻を過ぎたアラームを (再読み込みを待たずに) その場でカードから外すため、
    /// 残り時間の表示と同じ 1 秒周期で「次に鳴るアラーム」を判定し直す
    private var nextAlarmCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let nextAlarm = nextAlarm(now: context.date), let fireDate = nextAlarm.fixedFireDate {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        // ja: 次に鳴るアラーム
                        Text("Next alarm").eyebrowStyle()
                        Spacer()
                        // ja: %@後に鳴ります
                        Text("Rings in \(Text(fireDate, style: .relative))")
                            .font(.footnote)
                            .foregroundStyle(Color.paperTertiary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        // 午前・午後は端末の時刻設定に従う。12 時間表示で省略すると 13:30 が「01:30」になり発火時刻を誤認させる (24 時間表示では表示されない)
                        Text(fireDate, format: .dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits))
                            .font(.clockDigits)
                            .monospacedDigit()
                            .foregroundStyle(Color.paper)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        nextAlarmDayText(fireDate: fireDate, now: context.date)
                            .font(.body)
                            .foregroundStyle(Color.paperSecondary)
                    }
                    if let title = AlarmTitleStore.shared.title(id: nextAlarm.id) {
                        // 外部サービスから送られたタイトルはそのまま表示する
                        Text(verbatim: title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.paper)
                            .lineLimit(2)
                    } else {
                        // ja: タイトルなし
                        Text("Untitled alarm")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.paperTertiary)
                    }
                    // 送信元のトークン。サーバーの履歴に同じ id があるものだけ分かる (アプリ内のテストアラームには無い)。
                    // サービス名は `APIToken.name` がアプリからの発行では常にサーバーの既定値のため出さない (design_handoff/README.md「前提と未確定事項」)
                    if let prefix = history.first(where: { $0.id == nextAlarm.id.uuidString.lowercased() }).flatMap({ tokens.prefix(tokenID: $0.tokenID) }) {
                        Chip(text: Text(verbatim: prefix))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(border: .signalLine)
                .accessibilityIdentifier("home_next_alarm")
            } else {
                VStack(spacing: 16) {
                    // ja: 次に鳴るアラームはありません
                    Text("No upcoming alarm")
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                        // 識別子はカードではなく文言に付ける (コンテナに付けると中のボタンの識別子を上書きしてしまう)
                        .accessibilityIdentifier("home_next_alarm_empty")
                    Button {
                        Task { await scheduleTestAlarm() }
                    } label: {
                        // ja: 1 分後にテストアラームを鳴らす
                        Text("Ring a test alarm in 1 minute")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("home_next_alarm_ring_test")
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .card()
            }
        }
    }

    /// 登録済みアラームの一覧 (`scheduledAlarmsList`) を開く行。件数を添える。
    /// アプリ内から登録済みアラームを取り消せる導線として App Store 版にも残す (アカウント削除後の案内文が指す「アラーム一覧」)
    private var scheduledAlarmsRow: some View {
        NavigationLink {
            scheduledAlarmsList
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "alarm")
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
                    .frame(width: 24)
                // ja: 登録済みのアラーム
                Text("Scheduled alarms")
                    .font(.body)
                    .foregroundStyle(Color.paper)
                Spacer()
                Text(alarms.count, format: .number)
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
                RowChevron()
            }
            .rowPadding()
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityIdentifier("home_scheduled_alarms")
    }

    /// 登録済みアラームの確認と取り消し。行ごとの発火日時・タイトルと「取り消す」ボタン (取り消し失敗のエラーは一覧の下に出す)
    private var scheduledAlarmsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    if alarms.isEmpty {
                        // ja: 登録済みのアラームはありません
                        Text("No alarms scheduled")
                            .font(.body)
                            .foregroundStyle(Color.paperTertiary)
                            .rowPadding()
                            .accessibilityIdentifier("scheduled_alarms_empty")
                    }
                    ForEach(Array(alarms.enumerated()), id: \.element.id) { index, alarm in
                        if index > 0 {
                            HairlineDivider()
                        }
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                if let fireDate = alarm.fixedFireDate {
                                    Text(fireDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.headline)
                                        .foregroundStyle(Color.paper)
                                }
                                if let title = AlarmTitleStore.shared.title(id: alarm.id) {
                                    // 外部サービスから送られたタイトルはそのまま表示する
                                    Text(verbatim: title)
                                        .font(.footnote)
                                        .foregroundStyle(Color.paperTertiary)
                                        .lineLimit(2)
                                }
                            }
                            .accessibilityIdentifier("scheduled_alarm_\(alarm.id.uuidString)")
                            Spacer(minLength: 8)
                            Button {
                                cancel(alarm)
                            } label: {
                                // ja: アラームを取り消す
                                Text("Cancel alarm")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.paperTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("scheduled_alarm_cancel_\(alarm.id.uuidString)")
                        }
                        .rowPadding()
                    }
                }
                .card()
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .padding(.top, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 16)
                        .accessibilityIdentifier("scheduled_alarms_error")
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        // ja: 登録済みのアラーム
        .navigationTitle(Text("Scheduled alarms"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 次に鳴るアラーム。この端末に登録済みの固定日時のアラームのうち、発火時刻が `now` より後の最も早いもの
    private func nextAlarm(now: Date) -> Alarm? {
        alarms
            .filter { ($0.fixedFireDate ?? .distantPast) > now }
            .min { ($0.fixedFireDate ?? .distantFuture) < ($1.fixedFireDate ?? .distantFuture) }
    }

    /// 発火日の表記。今日 / 明日は語で、それ以外は月日で出す
    private func nextAlarmDayText(fireDate: Date, now: Date) -> Text {
        switch nextAlarmDay(fireDate: fireDate, now: now) {
        case .today:
            // ja: 今日
            return Text("Today")
        case .tomorrow:
            // ja: 明日
            return Text("Tomorrow")
        case .later:
            return Text(fireDate, format: .dateTime.month(.abbreviated).day())
        }
    }

    // MARK: - 直近の履歴

    private var historyCard: some View {
        VStack(spacing: 0) {
            if historyLoading && history.isEmpty {
                ProgressView()
                    .rowPadding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let historyError {
                Text(historyError)
                    .font(.footnote)
                    .foregroundStyle(Color.destructive)
                    .rowPadding()
                    .accessibilityIdentifier("home_history_error")
            } else if session.uid == nil {
                // 履歴はサインイン後にしか取れない。サインイン中に「履歴なし」と見せない
                // ja: サインイン中
                Text("Signing in")
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
                    .rowPadding()
            } else if history.isEmpty {
                // ja: 履歴はまだありません
                Text("No alarms yet")
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
                    .rowPadding()
                    .accessibilityIdentifier("home_history_empty")
            }
            ForEach(history) { entry in
                historyRow(entry)
                HairlineDivider()
            }
            if !ProEntitlement.isPro {
                Button {
                    paywallTrigger = .alarmHistory
                } label: {
                    HStack {
                        // ja: それより前の履歴は Pro で見られます
                        Text("Older alarms are kept in Pro")
                            .font(.subheadline)
                            .foregroundStyle(Color.paperTertiary)
                        Spacer()
                        RowChevron()
                    }
                    .rowPadding()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_history_upgrade")
            }
        }
        .card()
    }

    private func historyRow(_ entry: AlarmHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = entry.title {
                    // 外部サービスから送られたタイトルはそのまま表示する
                    Text(verbatim: title)
                        .font(.headline)
                        .foregroundStyle(Color.paper)
                        .lineLimit(1)
                } else {
                    // ja: タイトルなし
                    Text("Untitled alarm")
                        .font(.headline)
                        .foregroundStyle(Color.paperTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.fireAt, format: .dateTime.month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(Color.paperTertiary)
                    if let prefix = tokens.prefix(tokenID: entry.tokenID) {
                        Text(verbatim: prefix)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.paperTertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            // 発火時刻を迎えた瞬間に「登録済み」から「鳴りました」へ切り替えるため、次に鳴るアラームのカードと同じ 1 秒周期で判定し直す。
            // `.explicit([entry.fireAt])` は最初の描画から context.date が発火時刻になり、未来の登録が「鳴りました」と出る (simtunnel で確認) ため使わない
            TimelineView(.periodic(from: .now, by: 1)) { context in
                historyStatusText(entry, now: context.date)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.paperTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, DesignMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
        .accessibilityIdentifier("home_history_\(entry.id)")
    }

    /// 履歴 1 件の状態。サーバーの状態と、この端末からの反映結果・配送結果を組み合わせて決める。
    /// 発火したかどうかはサーバーにも端末にも記録が無い (AlarmKit は発火を通知しない) ため、発火時刻の経過で表す。
    /// 失敗系も色は変えず文言で伝える (橙は鳴ることにだけ使う。design_handoff/tokens.md「状態と強調」)
    private func historyStatusText(_ entry: AlarmHistoryEntry, now: Date) -> Text {
        switch entry.status {
        case .canceled:
            let report = entry.deviceReport(deviceID: DeviceIdentifier.current)
            if let report, report.action == .cancel, report.result == .failed {
                // この iPhone にはアラームが残っていて鳴り得るので、取り消し済みと言い切らない
                // ja: この iPhone で取り消しに失敗: %@
                return Text("Failed to cancel on this iPhone: \(report.error ?? "")")
            }
            if let report, report.action == .cancel {
                // ja: 取り消し済み
                return Text("Canceled")
            }
            if let delivery = entry.delivery, delivery.failureCount > 0 {
                // 配送結果は端末ごとではなく全端末の合計のため、他の端末には届いていても、報告の無いこの端末に届いていない可能性がある間は取り消し済みと言い切らない
                // ja: 取り消しの push がこの iPhone に届いていない可能性があります
                return Text("Cancel push may not have reached this iPhone")
            }
            if let report, report.action == .schedule, report.result == .applied {
                // この iPhone に登録済みのまま、取り消しの指示がまだ反映されていない
                // ja: 取り消し済み (この iPhone への反映を待っています)
                return Text("Canceled, waiting for this iPhone")
            }
            // ja: 取り消し済み
            return Text("Canceled")
        case .scheduled:
            if let report = entry.deviceReport(deviceID: DeviceIdentifier.current) {
                switch (report.action, report.result) {
                case (.schedule, .applied) where entry.fireAt <= now:
                    // ja: 鳴りました
                    return Text("Rang")
                case (.schedule, .applied):
                    // ja: この iPhone に登録済み
                    return Text("Scheduled on this iPhone")
                case (.schedule, .failed):
                    // ja: この iPhone で登録に失敗: %@
                    return Text("Failed on this iPhone: \(report.error ?? "")")
                case (.cancel, _):
                    // サーバーでは登録し直されているが、この端末はまだ取り消しまでしか反映していない
                    // ja: この iPhone への反映を待っています
                    return Text("Waiting for this iPhone")
                }
            }
            if let delivery = entry.delivery, delivery.failureCount > 0, delivery.successCount == 0 {
                // ja: push を配送できませんでした
                return Text("Push could not be delivered")
            }
            if entry.fireAt <= now {
                // ja: 発火時刻を過ぎました
                return Text("Alarm time has passed")
            }
            // ja: この iPhone への反映を待っています
            return Text("Waiting for this iPhone")
        }
    }

    // MARK: - 連携

    private var connectCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                APITokenView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "key.horizontal")
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                        .frame(width: 24)
                    // ja: API トークン
                    Text("API tokens")
                        .font(.body)
                        .foregroundStyle(Color.paper)
                    Spacer()
                    Text(tokens.count, format: .number)
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                    RowChevron()
                }
                .rowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account_api_tokens")
            HairlineDivider()
            NavigationLink {
                // 発行済みトークンの平文は発行直後の API トークン画面にしか無いため、ここからはプレースホルダ入りで表示する
                RecipesView(apiToken: nil, backend: session.settings.backend)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "powerplug")
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                        .frame(width: 24)
                    // ja: 連携レシピ
                    Text("Integration recipes")
                        .font(.body)
                        .foregroundStyle(Color.paper)
                    Spacer()
                    RowChevron()
                }
                .rowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open_recipes")
        }
        .card()
    }

    // MARK: - 読み込み

    /// バックエンドの履歴とトークン一覧を読み直す
    private func loadRemote() async {
        await loadHistory()
        await loadTokens()
    }

    /// バックエンドの履歴を読み直す。失敗はエラーとして表示し、前回の内容は残さない (古い履歴を最新として見せない)。
    /// 未サインインは起動直後に通る正常な経路のためエラーにせず、サインイン後の読み直しに任せる
    private func loadHistory() async {
        #if DEBUG
        // 多言語スクリーンショット撮影はサインインしないが、keychain に残った匿名アカウントで本番の履歴を読んでしまうと
        // 撮影結果がネットワークと keychain の状態に依存する (AlarmifyApp の方針) ため、履歴は読まず空のまま撮る
        if isSnapshotUITest { return }
        #endif
        historyLoading = true
        defer { historyLoading = false }
        do {
            let loaded = try await session.client.alarmHistory(limit: Self.historyLimit)
            guard !Task.isCancelled else { return }
            history = loaded
            historyError = nil
        } catch AlarmifyAPIError.notSignedIn {
            history = []
            historyError = nil
        } catch {
            // サインインの完了で `.task(id:)` が読み直す時、進行中の取得は取り消される。取り消しはエラーではなく、後続の取得結果に任せる
            guard !Task.isCancelled else { return }
            history = []
            historyError = error.localizedDescription
        }
    }

    /// トークン一覧を読み直す。送信元の表示と件数のためだけに使うので、失敗しても履歴の表示は妨げず、前回の内容を残さない
    private func loadTokens() async {
        #if DEBUG
        if isSnapshotUITest { return }
        #endif
        do {
            let loaded = try await session.client.apiTokens()
            guard !Task.isCancelled else { return }
            tokens = loaded
        } catch {
            guard !Task.isCancelled else { return }
            tokens = []
        }
    }

    private func refresh() {
        alarms = AlarmKitScheduler.alarms
    }

    /// 登録済みアラームを取り消す。取り消し失敗のエラーは `scheduledAlarmsList` と ホームの両方に出す
    private func cancel(_ alarm: Alarm) {
        do {
            try AlarmKitScheduler.cancel(id: alarm.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func scheduleTestAlarm() async {
        do {
            try await TestAlarm.schedule()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

/// 次に鳴るアラームの発火日を今日 / 明日 / それ以外に分ける
enum NextAlarmDay: Equatable {
    case today
    case tomorrow
    case later
}

/// `fireDate` が `now` の暦日で見て今日か明日か、それより後か。純粋関数で、同じ入力に同じ結果を返す (冪等)
func nextAlarmDay(fireDate: Date, now: Date, calendar: Calendar = .current) -> NextAlarmDay {
    if calendar.isDate(fireDate, inSameDayAs: now) {
        return .today
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(fireDate, inSameDayAs: tomorrow) {
        return .tomorrow
    }
    return .later
}

extension [APIToken] {
    /// 履歴の `tokenID` に対応するトークンの prefix。失効済み等で一覧に無ければ nil
    func prefix(tokenID: String) -> String? {
        first { $0.id == tokenID }?.prefix
    }
}

/// ContentView の Preview。多言語スクリーンショット撮影 (AlarmifySnapshotUITests) が
/// SnapshotUITestPage 経由で参照するため、#Preview マクロではなく型名を持つ PreviewProvider で定義する
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
