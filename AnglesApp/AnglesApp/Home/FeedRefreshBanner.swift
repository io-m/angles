import SwiftUI

/// What a pull-to-refresh actually did. Home and the library are strictly
/// newest-first, so a refresh with nothing newer legitimately returns the same
/// page. The outcome has to be stated, or a correct refresh reads as a dead
/// gesture — and a failed one reads the same as a successful one.
enum FeedRefreshOutcome: Equatable {
    case newItems(Int)
    case upToDate
    case failed
}

/// Brief pill under the fixed chrome, announcing the refresh outcome.
struct FeedRefreshBanner: View {
    let outcome: FeedRefreshOutcome?
    let token: Int
    /// "post" on the community feed, "card" in the private library.
    let noun: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: FeedRefreshOutcome?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        // `Color.clear` keeps this view in the hierarchy while the pill is
        // hidden. Without it the builder would collapse to `EmptyView`, whose
        // modifiers — including the `task` that shows the pill — never run.
        ZStack {
            Color.clear

            if let shown {
                pill(shown)
                    .transition(
                        .opacity.combined(with: .offset(y: -10))
                    )
            }
        }
        .frame(height: PillMetrics.height)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.34, dampingFraction: 0.86),
            value: shown
        )
        .allowsHitTesting(false)
        .accessibilityHidden(shown == nil)
        .task(id: token) {
            guard token > 0, let outcome else {
                return
            }
            shown = outcome
            // Long enough to read, short enough to stay out of the way.
            try? await Task.sleep(for: .seconds(1.8))
            shown = nil
        }
    }

    private enum PillMetrics {
        static let height: CGFloat = 34
    }

    private func pill(_ outcome: FeedRefreshOutcome) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(outcome))
                .font(.system(size: 12, weight: .semibold))
            Text(label(outcome))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(outcome == .failed ? theme.ink : theme.ink2)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(theme.faint, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        .accessibilityLabel(label(outcome))
    }

    private func symbol(_ outcome: FeedRefreshOutcome) -> String {
        switch outcome {
        case .newItems:
            "arrow.down.circle.fill"
        case .upToDate:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func label(_ outcome: FeedRefreshOutcome) -> String {
        switch outcome {
        case let .newItems(count):
            "\(count) new \(noun)\(count == 1 ? "" : "s")"
        case .upToDate:
            "You're all caught up"
        case .failed:
            "Couldn't refresh"
        }
    }
}
