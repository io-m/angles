import SwiftUI

/// Post (or Save privately, or the taste's Save) anchored where the input was.
struct ComposePostBar: View {
    let session: ComposeSession
    var isOnboardingTaste: Bool
    var isCelebratingSave: Bool
    var onPost: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Button(action: onPost) {
            HStack(spacing: 8) {
                if session.isSaving {
                    ProgressView()
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(session.isSaving ? "Saving" : title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                theme.surface,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .shadow(color: theme.shadowSoft, radius: 2, y: 1)
            .shadow(
                color: theme.shadowLift,
                radius: colorScheme == .dark ? 18 : 10,
                y: colorScheme == .dark ? 0 : 4
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityLabel(title)
        .accessibilityIdentifier("compose.post")
        .modifier(AccessibilityHintIfPresent(hint: hint))
    }

    private var isBusy: Bool {
        session.isSaving || isCelebratingSave || (!isOnboardingTaste && !session.canPostCook)
    }

    private var title: String {
        if isOnboardingTaste {
            return "Save to private library"
        }
        return session.composeIsPublic ? "Post" : "Save privately"
    }

    private var hint: String {
        if isOnboardingTaste {
            return ""
        }
        return session.composeIsPublic
            ? "Posts this card on Home"
            : "Saves this card on Profile"
    }
}

/// A taste has no field, so its note sits on an opaque chip above the Save bar.
struct ComposeNoteChip: View {
    let note: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ColorTokens.theme(colorScheme)
        Text(note)
            .font(.footnote.weight(.medium))
            .foregroundStyle(theme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .accessibilityLabel(note)
            .accessibilityIdentifier("compose.note")
    }
}

private struct AccessibilityHintIfPresent: ViewModifier {
    let hint: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if hint.isEmpty {
            content
        } else {
            content.accessibilityHint(hint)
        }
    }
}
