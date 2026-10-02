import SwiftUI

/// Shown once per account before its first thought leaves the phone, and before Home for an
/// account that never agreed. Names the AI providers, says what is sent, and carries the Terms
/// acceptance that community posting relies on. The server records the agreement.
struct AIConsentSheet: View {
    var cancelTitle: String = "Not now"
    /// False when the server did not record it; the sheet stays up with an error.
    var onAgree: () async -> Bool
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAgreeing = false
    @State private var agreeFailed = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Before you start")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundStyle(theme.ink)

                        Text("Angles writes your angles with AI on our servers.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        consentRow(
                            icon: "paperplane",
                            title: "What is sent",
                            detail: "The thought you write and your answers to follow-up questions. Your region is never sent to an AI provider."
                        )
                        consentRow(
                            icon: "cpu",
                            title: "Who processes it",
                            detail: "Mistral AI (France) or OpenAI (United States). Each request goes to one of them, and to the other if the first is unavailable."
                        )
                        consentRow(
                            icon: "globe",
                            title: "Posts are checked too",
                            detail: "When you post a card publicly, it is checked by the same AI before anyone else can see it."
                        )
                        consentRow(
                            icon: "hand.raised",
                            title: "Community rules",
                            detail: "There is no tolerance for objectionable content or abusive users. Reported posts are reviewed within 24 hours, and offending accounts are removed."
                        )
                        consentRow(
                            icon: "cross.case",
                            title: "Not therapy",
                            detail: "Angles is a self-reflection tool, not medical or mental-health care. If you might hurt yourself, contact local emergency services."
                        )
                    }

                    Text("By tapping Agree and continue, you allow Angles to send what you write to these providers and agree to the Terms of Use and Privacy Policy.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.faint)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 20) {
                        if let termsURL = AppConfig.termsOfServiceURL {
                            Link("Terms of Use", destination: termsURL)
                        }
                        if let privacyURL = AppConfig.privacyPolicyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        agree()
                    } label: {
                        ZStack {
                            Text("Agree and continue")
                                .opacity(isAgreeing ? 0 : 1)
                            if isAgreeing {
                                ProgressView()
                                    .tint(theme.paper)
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAgreeing)
                    .padding(.top, 4)

                    if agreeFailed {
                        Text("Couldn't reach Angles. Check your connection and try again.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AnglesCanvasBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(theme.muted)
                        .disabled(isAgreeing)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func agree() {
        guard !isAgreeing else {
            return
        }
        isAgreeing = true
        agreeFailed = false
        Task {
            let recorded = await onAgree()
            isAgreeing = false
            agreeFailed = !recorded
        }
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 40, height: 40)
                .background(theme.ink.opacity(theme.isDark ? 0.10 : 0.06), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.isDark ? theme.cardHairline : Color.black.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
