import SwiftUI

/// 設定画面。現在のプランの表示とペイウォールへの導線、法務ドキュメントへのリンクを持つ。
/// 見た目は仮 UI で、受領デザインの反映は #6 で行う
struct SettingsPage: View {
    /// entitlement 判定のキャッシュ (ProEntitlement.cacheEntitlement が更新する)。
    /// 購入・復元の直後に表示を追従させるため @AppStorage で購読する
    @AppStorage(.proEntitlementActive) private var proEntitlementActive = false
    /// entitlement の失効日時 (epoch 秒)。買い切り・未購入では保存されないため Optional
    @AppStorage(.proEntitlementExpiration) private var proEntitlementExpiration: Double?

    /// 表示中のペイウォールの文脈。nil の間はペイウォールを出さない
    @State private var paywallTrigger: PaywallTrigger?

    /// プラン表示の判定に使う現在時刻。
    /// @AppStorage の値は時計が失効日時を越えても変わらないため、画面を開いたまま失効した時に
    /// body を再評価させる状態としてここに持つ (PR #20 レビュー指摘)
    @State private var now = Date.now

    /// バックグラウンドから戻った時に now を取り直すための scene の状態
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                LabeledContent {
                    if isPro {
                        Text("Pro")
                    } else {
                        // ja: 無料
                        Text("Free")
                    }
                } label: {
                    // ja: プラン
                    Text("Plan")
                }
                .accessibilityIdentifier("settings_plan")

                if !isPro {
                    Button {
                        paywallTrigger = .settings
                    } label: {
                        // ja: Pro にアップグレード
                        Text("Upgrade to Pro")
                    }
                    .accessibilityIdentifier("settings_upgrade_button")
                }
            } header: {
                // ja: 課金
                Text("Subscription")
            }

            Section {
                // ja: 利用規約
                Link(destination: LegalLinks.terms) { Text("Terms of Use") }
                // ja: プライバシーポリシー
                Link(destination: LegalLinks.privacyPolicy) { Text("Privacy Policy") }
                // ja: 特定商取引法に基づく表記
                Link(destination: LegalLinks.specifiedCommercialTransactionAct) { Text("Legal Notice") }
            } header: {
                // ja: 法務情報
                Text("Legal")
            }

            #if DEBUG
            // 無料枠の上限に達した時のペイウォールは、上限判定を持つバックエンド (#2) がまだ無く到達できないため、
            // 検証用の導線をここへ置く (.claude/rules/debug-menu-for-verification.md)。
            // 開発者メニューを設ける時に TestFlight 配布でも解放するかを判断する
            Section {
                Button {
                    paywallTrigger = .freeQuotaExceeded
                } label: {
                    // ja: 無料枠の上限のペイウォールを表示
                    Text("Show the free quota paywall")
                }
                .accessibilityIdentifier("debug_show_free_quota_paywall")
            } header: {
                // ja: 開発者向け
                Text("Developer")
            }
            #endif
        }
        // ja: 設定
        .navigationTitle(Text("Settings"))
        .sheet(item: $paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
        }
        .task(id: proEntitlementExpiration) {
            await refreshNowAtExpiration()
        }
        .onChange(of: scenePhase) { _, phase in
            // Task.sleep はアプリが停止している間は進まないため、前面に戻った時にも取り直す
            if phase == .active {
                now = .now
            }
        }
    }

    /// 失効日時まで待ってから now を取り直す。
    /// 失効日時が無い (買い切り・未購入) 場合と、すでに過ぎている場合は待たない。
    /// 何度呼んでも now が現在時刻になるだけで、同じ状態へ収束する (冪等)
    private func refreshNowAtExpiration() async {
        guard let expirationDate = proEntitlementExpiration.map(Date.init(timeIntervalSince1970:)) else { return }
        let interval = expirationDate.timeIntervalSince(.now)
        guard interval > 0 else {
            now = .now
            return
        }
        try? await Task.sleep(for: .seconds(interval))
        now = .now
    }

    /// キャッシュした entitlement が今この瞬間も有効か
    private var isPro: Bool {
        cachedProActive(
            active: proEntitlementActive,
            expirationDate: proEntitlementExpiration.map(Date.init(timeIntervalSince1970:)),
            now: now
        )
    }
}

#Preview {
    NavigationStack {
        SettingsPage()
    }
}
