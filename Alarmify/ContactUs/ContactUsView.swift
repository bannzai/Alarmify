import SwiftUI

/// お問い合わせフォーム。種別・内容・返信先のメールアドレスをバックエンドへ送り、運営者へ通知する
/// (bannzai/Focus のお問い合わせと同じ項目)。メールで問い合わせたい人向けに、宛先のメールアドレスも同じ画面に出す
struct ContactUsView: View {
    @State private var session = AccountSession.shared
    /// 選んでいる種別。問い合わせの多くは不具合の報告のため、bannzai/Focus と同じくバグ・不具合を初期値にする
    @State private var inquiryType: ContactInquiry.InquiryType = .bug
    /// 入力中の本文
    @State private var content = ""
    /// 入力中の返信先のメールアドレス
    @State private var emailAddress = ""
    /// 送信中か。送信ボタンの二重タップを防ぎ、進行中の表示に使う
    @State private var submitting = false
    /// 送信の完了を伝えるアラートの表示状態
    @State private var submitted = false
    /// 入力の不備・送信の失敗の説明。問題が無ければ nil
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ja: 種別
                SectionHeader(Text("Type"), dense: true)
                inquiryTypeCard

                // ja: 内容
                SectionHeader(Text("Message"), dense: true)
                TextEditor(text: $content)
                    .font(.body)
                    .foregroundStyle(Color.paper)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(8)
                    .card()
                    .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                    .accessibilityIdentifier("contact_us_content")
                // ja: 不具合の場合はどの画面で何が起きたかを教えてください
                footnote(Text("For a bug tell us which screen you were on and what happened"))

                // ja: 返信先のメールアドレス
                SectionHeader(Text("Reply-to email"), dense: true)
                TextField(text: $emailAddress) {
                    Text(verbatim: "you@example.com")
                }
                .font(.body)
                .foregroundStyle(Color.paper)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .rowPadding()
                .card()
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .accessibilityIdentifier("contact_us_email")
                // ja: %@ から返信します
                footnote(Text("We reply from \(LegalLinks.supportEmail)"))

                Button {
                    Task { await submit() }
                } label: {
                    if submitting {
                        ProgressView()
                    } else {
                        // ja: 送信
                        Text("Send")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(submitting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || emailAddress.isEmpty)
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .padding(.top, 20)
                .accessibilityIdentifier("contact_us_submit")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 12)
                        .accessibilityIdentifier("contact_us_error")
                }

                // ja: メールで問い合わせる
                SectionHeader(Text("Prefer email"))
                Link(destination: LegalLinks.supportMail(accountID: session.uid)) {
                    HStack {
                        Text(verbatim: LegalLinks.supportEmail)
                            .font(.body)
                            .foregroundStyle(Color.paper)
                        Spacer()
                        RowChevron()
                    }
                    .rowPadding()
                }
                .card()
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .accessibilityIdentifier("contact_us_email_link")
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        // ja: お問い合わせ
        .navigationTitle(Text("Contact Us"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            // ja: お問い合わせありがとうございます
            Text("Thanks for reaching out"),
            isPresented: $submitted
        ) {
            Button {
                dismiss()
            } label: {
                // ja: OK
                Text("OK")
            }
        } message: {
            // ja: 内容を確認してメールで返信します
            Text("We will read your message and reply by email")
        }
    }

    /// 種別を 1 つ選ぶカード。選んでいる行にチェックを出す
    private var inquiryTypeCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(ContactInquiry.InquiryType.allCases.enumerated()), id: \.element) { index, type in
                if index > 0 {
                    HairlineDivider()
                }
                Button {
                    inquiryType = type
                } label: {
                    HStack {
                        inquiryTypeText(type)
                            .font(.body)
                            .foregroundStyle(Color.paper)
                        Spacer()
                        if inquiryType == type {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.signalText)
                        }
                    }
                    .rowPadding()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("contact_us_type_\(type.rawValue)")
                .accessibilityAddTraits(inquiryType == type ? .isSelected : [])
            }
        }
        .card()
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
    }

    /// 種別の表示名
    private func inquiryTypeText(_ type: ContactInquiry.InquiryType) -> Text {
        switch type {
        case .bug:
            // ja: バグ・不具合
            return Text("Bug or issue")
        case .feedback:
            // ja: ご意見・ご要望
            return Text("Feedback or request")
        case .other:
            // ja: その他
            return Text("Other")
        }
    }

    /// 入力欄の下の補足
    private func footnote(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(Color.paperTertiary)
            .padding(.horizontal, DesignMetrics.textHorizontalPadding)
            .padding(.top, 8)
    }

    /// 入力を検査してから送信する。成功したら完了のアラートを出し、失敗したら errorMessage に理由を出す
    private func submit() async {
        let trimmedEmailAddress = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // サーバーの zod は JavaScript の文字列長 (UTF-16 のコード単位) で数えるため、同じ単位で比べる
        guard trimmedContent.utf16.count <= Self.contentMaxLength else {
            // ja: 内容は %lld 文字以内にしてください
            errorMessage = String(localized: "Keep your message within \(Self.contentMaxLength) characters")
            return
        }
        guard Self.isValidEmailAddress(emailAddress: trimmedEmailAddress) else {
            // ja: メールアドレスの形式を確認してください
            errorMessage = String(localized: "Check the format of your email address")
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            try await session.client.submitContactInquiry(
                inquiry: ContactInquiry(
                    inquiryType: inquiryType,
                    content: trimmedContent,
                    emailAddress: trimmedEmailAddress,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                )
            )
            errorMessage = nil
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 本文の上限。サーバーの createContactInquiryRequestSchema の content の上限 (firebase/functions/src/schema/request.ts) と同じ値にする
    static let contentMaxLength = 4000

    /// 返信先として送ってよい形のメールアドレスか。送信前に入力ミスを知らせるための簡易な判定で、正否の最終判定はサーバーが行う
    static func isValidEmailAddress(emailAddress: String) -> Bool {
        emailAddress.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}

#Preview {
    NavigationStack {
        ContactUsView()
    }
}
