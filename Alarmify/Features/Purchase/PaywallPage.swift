import RevenueCat
import SwiftUI

/// ペイウォールを開いた文脈。表示する導入文が変わる。
/// sheet(item:) へ渡すため Identifiable に準拠する
enum PaywallTrigger: Identifiable {
    /// 設定画面から明示的に開いた
    case settings
    /// 無料プランの上限 (トークン数・月間のアラーム数) に達した操作から開いた。
    /// アプリが受け取るのは API トークン発行の `plan_limit_exceeded` (APITokenModel.issue)
    case freeQuotaExceeded
    /// ホームの履歴 (無料プランは直近数件だけ) から、もっと多くの履歴を求めて開いた
    case alarmHistory

    var id: Self { self }
}

/// ペイウォール画面。年額を主・月額を副として提示する (課金設計は documents/PROJECT.md、構成と文言は design_handoff/screens/paywall.md と paywall-review.md)。
/// 価格・購読期間・月額換算はストアが正のため RevenueCat の offering から取得できた package だけを描画し、
/// 取得できない間は購入導線を出さずに再読み込みへ倒す
/// (~/.claude/rules/coding-rules-no-default-for-external-source-of-truth.md)
struct PaywallPage: View {
    /// このペイウォールを開いた文脈
    let trigger: PaywallTrigger

    /// RevenueCat の offering。読み込み中・取得失敗・API key 未設定の間は nil
    @State private var offering: Offering?
    /// 選択中のプラン。offering の読み込み後に年額 (無ければ月額) を既定で選ぶ
    @State private var selectedPackage: Package?
    /// 購入・復元の処理中かどうか。二重実行を防ぎ、ボタンを無効化する
    @State private var isPurchasing = false
    /// offering を取得できなかったかどうか。再読み込みの導線を出す
    @State private var offeringUnavailable = false
    /// 購入・復元の失敗をユーザーへ伝えるメッセージ。nil 以外でアラート表示する
    @State private var purchaseError: String?

    @Environment(\.dismiss) private var dismiss

    init(trigger: PaywallTrigger = .settings) {
        self.trigger = trigger
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paperSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.hairline, in: Circle())
                }
                // ja: 閉じる
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("paywall_close_button")
            }
            .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
            .frame(height: 44)

            // 特典とプランカードの間の余白は画面の高さに応じて伸ばし (プランカードと CTA を下に寄せる)、
            // 収まらない高さ (日本語の長い見出し等) ではスクロールさせる
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(minHeight: proxy.size.height)
                }
            }
        }
        .screenBackground()
        .task { await loadOffering() }
        .alert(purchaseError ?? "", isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button(String(localized: "OK")) { purchaseError = nil }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // 製品名 + Pro。翻訳しない
                Text(verbatim: "Signalarm Pro").eyebrowStyle()
                // ja: もっと多くのサービスと すべてのアラームの記録を
                Text("More services and every alarm kept")
                    .font(.title.bold())
                    .foregroundStyle(Color.paper)
                lead
                    .font(.subheadline)
                    .foregroundStyle(Color.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DesignMetrics.heroHorizontalPadding)

            VStack(alignment: .leading, spacing: 14) {
                // ja: サービスごとのトークン
                benefit(systemImage: "key.horizontal", text: Text("A token for every service"))
                // ja: 無制限のアラーム
                benefit(systemImage: "infinity", text: Text("Unlimited alarms"))
                // ja: すべてのアラーム履歴
                benefit(systemImage: "clock.arrow.circlepath", text: Text("Full alarm history"))
                // ja: すべての iPhone で鳴る
                benefit(systemImage: "iphone.gen3.radiowaves.left.and.right", text: Text("Rings on all your iPhones"))
            }
            .padding(.horizontal, DesignMetrics.heroHorizontalPadding)
            .padding(.top, 24)

            Spacer(minLength: 32)

            plans
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)

            Button {
                if let selectedPackage {
                    Task { await purchase(package: selectedPackage) }
                }
            } label: {
                continueLabel
                    .opacity(isPurchasing ? 0 : 1)
                    .overlay {
                        if isPurchasing {
                            ProgressView()
                                .tint(Color.onSignal)
                        }
                    }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedPackage == nil || isPurchasing)
            .accessibilityIdentifier("paywall_continue_button")
            .padding(.horizontal, DesignMetrics.textHorizontalPadding)
            .padding(.top, 16)

            // ja: 設定で解約するまで自動更新されます。価格はお住まいの地域の通貨で表示されます。
            Text("Renews automatically until canceled in Settings. Prices shown in your local currency.")
                .font(.caption2)
                .foregroundStyle(Color.paperQuaternary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DesignMetrics.heroHorizontalPadding)
                .padding(.top, 12)

            HStack(spacing: 18) {
                Button {
                    Task { await restore() }
                } label: {
                    // ja: 購入を復元
                    Text("Restore")
                }
                .disabled(isPurchasing)
                .accessibilityIdentifier("paywall_restore")
                // ja: 利用規約
                Link(destination: LegalLinks.terms) { Text("Terms") }
                // ja: プライバシー
                Link(destination: LegalLinks.privacyPolicy) { Text("Privacy") }
                // ja: 特定商取引法に基づく表記
                Link(destination: LegalLinks.specifiedCommercialTransactionAct) { Text("Legal notice") }
                    .accessibilityIdentifier("paywall_specified_commercial_transaction_act_link")
            }
            .font(.footnote)
            .foregroundStyle(Color.paperTertiary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
        .padding(.bottom, 24)
    }

    // MARK: - 本文

    /// リード。1 文目はペイウォールを開いた文脈で変え、2 文目は共通
    private var lead: Text {
        // ja: Pro ではどちらの上限もなくなります。
        let common = Text("Pro removes both limits.")
        switch trigger {
        case .settings:
            // ja: 無料プランではトークン 1 つ・月 20 回までアラームを登録できます。%@
            return Text("The free plan includes one token and 20 alarms a month. \(common)")
        case .freeQuotaExceeded:
            // トークン数と月間のアラーム数のどちらの上限でも開くため、上限の種類を特定しない文言にする
            // ja: 無料プランの上限に達しました。%@
            return Text("You've reached the limit of the free plan. \(common)")
        case .alarmHistory:
            // 件数はサーバーの planLimits.free.alarmHistory (functions/src/lib/plan.ts) と揃える。
            // ホームは Pro でも直近 20 件 (ContentView.historyLimit) までの表示のため、全期間・30 日分とは言わない
            // ja: 無料プランで見られる履歴は直近 3 件です。%@
            return Text("The free plan shows the 3 most recent alarms. \(common)")
        }
    }

    private func benefit(systemImage: String, text: Text) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.signal)
                .frame(width: 24)
            text
                .font(.body)
                .foregroundStyle(Color.paper)
        }
    }

    /// 取得できた package だけのプランカード。年額を上・月額を下に並べる。取得できない間は再読み込みの導線
    @ViewBuilder
    private var plans: some View {
        if let offering {
            VStack(spacing: 8) {
                if let annual = offering.annual {
                    planCard(
                        package: annual,
                        // ja: 年額
                        name: Text("Yearly"),
                        bestValue: true,
                        // 月額換算はストアの価格から SDK が計算した値だけを出す (取得できなければ注記を出さない)
                        // ja: 月あたり %@ (年払い)
                        note: annual.storeProduct.localizedPricePerMonth.map { Text("\($0) a month billed yearly") },
                        // ja: 年
                        period: Text("per year"),
                        identifier: "paywall_yearly_button"
                    )
                }
                if let monthly = offering.monthly {
                    planCard(
                        package: monthly,
                        // ja: 月額
                        name: Text("Monthly"),
                        bestValue: false,
                        // ja: いつでも解約できます
                        note: Text("Cancel anytime"),
                        // ja: 月
                        period: Text("per month"),
                        identifier: "paywall_monthly_button"
                    )
                }
            }
        } else if offeringUnavailable {
            VStack(spacing: 14) {
                // ja: 価格を読み込めませんでした
                Text("Prices couldn't be loaded")
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
                Button {
                    Task { await loadOffering() }
                } label: {
                    // ja: 料金を再読み込み
                    Text("Reload prices")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("paywall_reload_offering")
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .card()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// プラン 1 枚。選択中は枠を `signal` にし、ラジオを塗る
    private func planCard(package: Package, name: Text, bestValue: Bool, note: Text?, period: Text, identifier: String) -> some View {
        let selected = selectedPackage?.identifier == package.identifier
        return Button {
            selectedPackage = package
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.signal : Color.clear)
                    Circle()
                        .strokeBorder(selected ? Color.signal : Color.hairlineStrong, lineWidth: 1.5)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.onSignal)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        name
                            .font(.headline)
                            .foregroundStyle(Color.paper)
                        if bestValue {
                            // ja: おすすめ
                            Chip(text: Text("Best value"))
                        }
                    }
                    if let note {
                        note
                            .font(.footnote)
                            .foregroundStyle(Color.paperTertiary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: package.storeProduct.localizedPriceString)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.paper)
                    period
                        .font(.footnote)
                        .foregroundStyle(Color.paperTertiary)
                }
            }
            .padding(.horizontal, DesignMetrics.rowHorizontalPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: DesignMetrics.cardCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.cardCornerRadius, style: .continuous).strokeBorder(selected ? Color.signal : Color.hairlineStrong, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// CTA の文言。選択中のプランに合わせる。プランを選べない間 (読み込み中・取得失敗) は年額の文言のまま無効にする
    private var continueLabel: Text {
        if let selectedPackage, selectedPackage.identifier == offering?.monthly?.identifier {
            // ja: 月額で続ける
            return Text("Continue with Monthly")
        }
        // ja: 年額で続ける
        return Text("Continue with Yearly")
    }

    // MARK: - 購入

    /// 購入・復元を始められない時のメッセージ。始めてよければ nil。
    /// 匿名 ID のまま購入するとサーバー側のプランが更新されないため、uid に結び付くまで購入・復元を始めない (AccountSession.purchaseLinkState)
    private func purchaseBlockedMessage() async -> String? {
        switch await AccountSession.shared.purchaseLinkState() {
        case .linked:
            return nil
        case .notLinked:
            // ja: 購入をアカウントに結び付けられませんでした。通信状態を確認してもう一度お試しください。
            return String(localized: "Couldn't link purchases to your account. Check your connection and try again.")
        case .emulatorBackend:
            // 開発者メニューでエミュレータを選んだ時だけ到達する (App Store 配布では接続先を変えられない)
            // ja: エミュレータに接続している間は購入と復元を行えません。開発者メニューで接続先を production に戻してください。
            return String(localized: "Purchases and restores are unavailable while connected to the emulator. Switch the backend back to production in the developer menu.")
        }
    }

    /// offering を読み込む。
    /// lookup_key (ProEntitlement.offeringIdentifier) の識別子だけで取得する。`.current` へのフォールバックは
    /// Dashboard の Current 指定次第で別キャンペーン用 offering の商品を売ってしまうため使わない。
    /// API key 未設定・取得失敗・購入できる package が 1 つも無い場合は購入導線を出さず、再読み込みへ倒す
    private func loadOffering() async {
        guard Purchases.isConfigured else {
            offering = nil
            selectedPackage = nil
            offeringUnavailable = true
            return
        }
        offeringUnavailable = false
        do {
            let resolved = try await Purchases.shared.offerings().offering(identifier: ProEntitlement.offeringIdentifier)
            if let resolved, resolved.annual != nil || resolved.monthly != nil {
                offering = resolved
                // 既定は年額 (課金設計の主プラン)。年額が無い offering では月額を選ぶ
                selectedPackage = resolved.annual ?? resolved.monthly
            } else {
                offering = nil
                selectedPackage = nil
                offeringUnavailable = true
            }
        } catch {
            offering = nil
            selectedPackage = nil
            offeringUnavailable = true
        }
    }

    /// package を購入し、entitlement pro が有効になったら閉じる
    private func purchase(package: Package) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        if let blocked = await purchaseBlockedMessage() {
            purchaseError = blocked
            return
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            // キャンセルはユーザー操作の範囲なので何もしない
            if result.userCancelled {
                return
            }
            // customerInfoStream 経由のキャッシュ更新は非同期で、dismiss 直後の描画に間に合わないことがあるため、
            // 確定した CustomerInfo を先にキャッシュへ反映する
            ProEntitlement.cacheEntitlement(customerInfo: result.customerInfo)
            if result.customerInfo.entitlements[ProEntitlement.entitlementIdentifier]?.isActive == true {
                dismiss()
            } else {
                // 商品と entitlement の紐付け不備・反映遅延で、購入が成功しても pro が有効にならないケースを黙殺しない
                // ja: 購入は完了しましたが、Pro の反映を確認できませんでした。時間をおいて購入の復元をお試しください。
                purchaseError = String(localized: "The purchase finished, but Pro couldn't be confirmed. Please try restoring purchases later.")
            }
        } catch {
            // ja: 購入を完了できませんでした。
            purchaseError = String(localized: "The purchase couldn't be completed.") + "\n\(error.localizedDescription)"
        }
    }

    /// 過去の購入を復元し、entitlement pro が有効になったら閉じる
    private func restore() async {
        guard !isPurchasing else { return }
        guard Purchases.isConfigured else {
            // ja: 購入はまだ準備できていません。しばらくしてからお試しください。
            purchaseError = String(localized: "Purchases aren't ready yet. Please try again later.")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        if let blocked = await purchaseBlockedMessage() {
            purchaseError = blocked
            return
        }
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            // 返金・失効で entitlement が無効になっている場合に古い true を残さないため、
            // 有効・無効のどちらでも確定した CustomerInfo をキャッシュへ反映する (PR #20 レビュー指摘)
            ProEntitlement.cacheEntitlement(customerInfo: customerInfo)
            if customerInfo.entitlements[ProEntitlement.entitlementIdentifier]?.isActive == true {
                dismiss()
            } else {
                // ja: 復元できる購入が見つかりませんでした。
                purchaseError = String(localized: "No purchases to restore were found.")
            }
        } catch {
            // ja: 購入を復元できませんでした。
            purchaseError = String(localized: "Purchases couldn't be restored.") + "\n\(error.localizedDescription)"
        }
    }
}

#Preview {
    PaywallPage(trigger: .freeQuotaExceeded)
}
