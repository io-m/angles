import SwiftUI

/// The empty compose screen's welcome, gone once there is a thought.
struct ComposeWelcome: View {
    let session: ComposeSession
    var isOnboardingTaste: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if session.phase == .composing && session.statement.isEmpty {
            let theme = ColorTokens.theme(colorScheme)
            VStack(spacing: 20) {
                InspireMark(size: 56)

                VStack(spacing: 8) {
                    Text(isOnboardingTaste ? "Welcome to Angles" : "Break the spiral.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .tracking(-0.4)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)

                    if isOnboardingTaste {
                        Text("Your first thought is free.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }

    private var detail: String {
        if isOnboardingTaste {
            return "Write down a thought that keeps looping in your head. Angles may ask a quick follow-up, then shows it to you from a few new angles."
        }
        return "When a thought keeps looping in your head, see it from another angle."
    }
}
