import Foundation

/// 利用規約・プライバシーポリシー等の外部リンク (docs/ を GitHub Pages で配信している)。
/// 設定画面とペイウォールの両方から参照するため 1 箇所にまとめる。
/// 利用規約とプライバシーポリシーは、アプリの表示言語が日本語なら ja 版・それ以外は共通の英語版を開く
enum LegalLinks {
    /// 利用規約
    static var terms: URL { terms(displayLanguageCode: appDisplayLanguageCode) }
    /// プライバシーポリシー
    static var privacyPolicy: URL { privacyPolicy(displayLanguageCode: appDisplayLanguageCode) }
    /// 特定商取引法に基づく表記 (日本の法令に基づく表記のため日本語のみ)
    static let specifiedCommercialTransactionAct = URL(string: "https://bannzai.github.io/Alarmify/SpecifiedCommercialTransactionAct-ja")!

    /// 利用規約 (表示言語コード指定)。テストから表示言語を固定して検証するために分離している
    static func terms(displayLanguageCode: String) -> URL {
        URL(string: "https://bannzai.github.io/Alarmify/Terms-\(legalDocumentLanguage(displayLanguageCode: displayLanguageCode))")!
    }

    /// プライバシーポリシー (表示言語コード指定)。テストから表示言語を固定して検証するために分離している
    static func privacyPolicy(displayLanguageCode: String) -> URL {
        URL(string: "https://bannzai.github.io/Alarmify/PrivacyPolicy-\(legalDocumentLanguage(displayLanguageCode: displayLanguageCode))")!
    }

    /// 法務文書の言語サフィックス。日本語表示なら ja 版、それ以外は各言語版を用意していないため共通の en 版。
    /// "ja" との完全一致で判定する (Localizable.xcstrings の日本語の言語識別子が "ja" のため、
    /// preferredLocalizations が返す日本語の値は "ja" に限られる)
    private static func legalDocumentLanguage(displayLanguageCode: String) -> String {
        displayLanguageCode == "ja" ? "ja" : "en"
    }

    /// アプリの実際の表示言語コード。Locale.current は端末の言語設定そのものを返すため、
    /// アプリが対応するローカリゼーションと突き合わせた結果である Bundle.main.preferredLocalizations を使う。
    /// フォールバックの "en" はアプリの基本言語 (localization-guidelines.md) に合わせている
    private static var appDisplayLanguageCode: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}
