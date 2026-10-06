import Foundation

/// お問い合わせフォームから送る問い合わせ。
/// appApi の `POST /v1/contact-inquiries` の本文 (firebase/functions/src/schema/request.ts の `createContactInquiryRequestSchema`) に対応する
struct ContactInquiry: Equatable, Sendable {
    /// お問い合わせの種別。値はサーバーの `contactInquiryTypeSchema` と同じ
    enum InquiryType: String, CaseIterable, Sendable {
        /// バグ・不具合
        case bug
        /// ご意見・ご要望
        case feedback
        /// その他
        case other
    }

    let inquiryType: InquiryType
    /// 問い合わせの本文
    let content: String
    /// 返信先のメールアドレス
    let emailAddress: String
    /// 送信したアプリのバージョン (CFBundleShortVersionString)。取得できなければ nil
    let appVersion: String?
}
