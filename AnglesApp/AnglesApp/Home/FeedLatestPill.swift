import SwiftUI

/// Sticky, tappable cousin of `FeedRefreshBanner`. Launch parks a newer For you mix
/// instead of swapping cards under a finger; this is how the user asks for it.
struct FeedLatestPill: View {
    var isVisible: Bool
    var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            Color.clear

            if isVisible {
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("See latest")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(theme.faint, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See latest")
                .accessibilityHint("New For you mix available.")
                .transition(
                    .opacity.combined(with: .offset(y: -10))
                )
            }
        }
        .frame(height: 34)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.34, dampingFraction: 0.86),
            value: isVisible
        )
        .allowsHitTesting(isVisible)
    }
}
