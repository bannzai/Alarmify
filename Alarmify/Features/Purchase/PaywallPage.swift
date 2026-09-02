import RevenueCat
import SwiftUI

/// ペイウォールを開いた文脈。表示する導入文が変わる。
/// sheet(item:) へ渡すため Identifiable に準拠する
enum PaywallTrigger: Identifiable {
    /// 設定画面から明示的に開いた
    case settings
    /// 無料プランの上限に達した操作から開いた
    case freeQuotaExceeded

    var id: Self { self }
}

/// ペイウォール画面。年額を主・月額を副として提示する (課金設計は documents/PROJECT.md)。
/// 価格・購読期間はストアが正のため RevenueCat の offering から取得できた package だけを描画し、
/// 取得できない間は購入導線を出さずに再読み込みへ倒す
/// (~/.claude/rules/coding-rules-no-default-for-external-source-of-truth.md)。
/// 見た目は仮 UI で、受領デザインの反映は #6 で行う
struct PaywallPage: View {
    /// このペイウォールを開いた文脈
    let trigger: PaywallTrigger

    /// RevenueCat の offering。読み込み中・取得失敗・API key 未設定の間は nil
    @State private var offering: Offering?
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
        NavigationStack {
            List {
                Section {
                    triggerText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // ja: サービスごとのトークン、無制限のアラーム登録、アラーム履歴、複数端末への配送を解放します
                    Text("Unlock a token per service, unlimited alarm scheduling, alarm history, and delivery to multiple devices")
                } header: {
                    Text("Pro")
                }

                Section {
                    if let offering {
                        planButtons(offering: offering)
                    } else if offeringUnavailable {
                        // ja: 価格を読み込めませんでした
                        Text("Prices couldn't be loaded")
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await loadOffering() }
                        } label: {
                            // ja: 料金を再読み込み
                            Text("Reload prices")
                        }
                        .accessibilityIdentifier("paywall_reload_offering")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    // ja: プラン
                    Text("Plans")
                }

                Section {
                    Button {
                        Task { await restore() }
                    } label: {
                        // ja: 購入を復元
                        Text("Restore Purchases")
                    }
                    .disabled(isPurchasing)
                    .accessibilityIdentifier("paywall_restore")

                    // ja: 利用規約
                    Link(destination: LegalLinks.terms) { Text("Terms of Use") }
                    // ja: プライバシーポリシー
                    Link(destination: LegalLinks.privacyPolicy) { Text("Privacy Policy") }
                    // ja: 特定商取引法に基づく表記
                    Link(destination: LegalLinks.specifiedCommercialTransactionAct) { Text("Legal Notice") }
                        .accessibilityIdentifier("paywall_specified_commercial_transaction_act_link")
                }
            }
            // ja: Pro にアップグレード
            .navigationTitle(Text("Upgrade to Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        // ja: 閉じる
                        Text("Close")
                    }
                    .accessibilityIdentifier("paywall_close_button")
                }
            }
        }
        .task { await loadOffering() }
        .alert(purchaseError ?? "", isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button(String(localized: "OK")) { purchaseError = nil }
        }
    }

    /// ペイウォールを開いた文脈の導入文
    private var triggerText: Text {
        switch trigger {
        case .settings:
            // ja: 無料プランではトークン 1 つ・月 20 回までアラームを登録できます
            return Text("The free plan includes one token and up to 20 alarms a month")
        case .freeQuotaExceeded:
            // ja: 今月の無料枠を使い切りました
            return Text("You've used up this month's free quota")
        }
    }

    /// 取得できた package だけの購入ボタン。年額を主・月額を副として並べる
    @ViewBuilder
    private func planButtons(offering: Offering) -> some View {
        if let annual = offering.annual {
            Button {
                Task { await purchase(package: annual) }
            } label: {
                // ja: 年 %@
                Text("\(annual.storeProduct.localizedPriceString) / year")
                    .font(.headline)
            }
            .disabled(isPurchasing)
            .accessibilityIdentifier("paywall_yearly_button")
        }

        if let monthly = offering.monthly {
            Button {
                Task { await purchase(package: monthly) }
            } label: {
                // ja: 月 %@
                Text("\(monthly.storeProduct.localizedPriceString) / month")
            }
            .disabled(isPurchasing)
            .accessibilityIdentifier("paywall_monthly_button")
        }
    }

    /// offering を読み込む。
    /// lookup_key (ProEntitlement.offeringIdentifier) の識別子だけで取得する。`.current` へのフォールバックは
    /// Dashboard の Current 指定次第で別キャンペーン用 offering の商品を売ってしまうため使わない。
    /// API key 未設定・取得失敗・購入できる package が 1 つも無い場合は購入導線を出さず、再読み込みへ倒す
    private func loadOffering() async {
        guard Purchases.isConfigured else {
            offering = nil
            offeringUnavailable = true
            return
        }
        offeringUnavailable = false
        do {
            let resolved = try await Purchases.shared.offerings().offering(identifier: ProEntitlement.offeringIdentifier)
            if let resolved, resolved.annual != nil || resolved.monthly != nil {
                offering = resolved
            } else {
                offering = nil
                offeringUnavailable = true
            }
        } catch {
            offering = nil
            offeringUnavailable = true
        }
    }

    /// package を購入し、entitlement pro が有効になったら閉じる
    private func purchase(package: Package) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
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
