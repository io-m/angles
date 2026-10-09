import SwiftUI

/// Sizes, shapes, and motion shared by the compose screen's pieces.
enum ComposeLayout {
    static let edgePad: CGFloat = 20
    static let rowSpacing: CGFloat = 14
    /// The AI avatar and the gap after it; replies line up with the bubble beside it.
    static let aiAvatarColumn: CGFloat = 50
    /// Room kept free beside an AI bubble so it never spans the whole row.
    static let aiSideGap: CGFloat = 36
    /// Room kept free beside the user's bubble.
    static let userSideGap: CGFloat = 36
    /// The input and the bottom buttons are 56 pt tall with 8 pt above and below.
    static let bottomBarHeight: CGFloat = 72

    /// One short, soft ease for a row arriving. Rows already on screen never take part in it.
    static let insertAnimation = Animation.smooth(duration: 0.35)

    /// The AI's side of the screen is always this shape: the bubble corner with a small tail at
    /// the lower left, scaled up for the longer question, error, and angles cards.
    static let aiCardShape = UnevenRoundedRectangle(
        topLeadingRadius: 24,
        bottomLeadingRadius: 6,
        bottomTrailingRadius: 24,
        topTrailingRadius: 24,
        style: .continuous
    )

    static func bubbleShape(isAI: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isAI ? 5 : 18,
            bottomTrailingRadius: isAI ? 18 : 5,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    /// A new row fades in while sliding a little from its own side: yours from the right, the
    /// AI's from the left. It never animates out, and no other row takes part.
    static func arrival(from edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        let slide = reduceMotion ? 0 : (edge == .leading ? -16.0 : 16.0)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: slide)),
            removal: .identity
        )
    }
}

enum ComposeMotion {
    static func fade(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.12) : .linear(duration: 0.25)
    }

    static func contentFade(_ reduceMotion: Bool, presented: Bool) -> Animation {
        if presented {
            return fade(reduceMotion)
        }

        return reduceMotion ? .linear(duration: 0.08) : .linear(duration: 0.14)
    }
}

struct ComposeFrost: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)

            theme.surface
                .opacity(colorScheme == .dark ? 0.14 : 0.10)
        }
        .accessibilityHidden(true)
    }
}

/// The brand glow under the bottom bar. It sits behind the thread, so it can never tint or
/// cover a line of text.
struct ComposeGlow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = InspireMark.brandColor
        let dark = colorScheme == .dark
        EllipticalGradient(
            stops: [
                .init(color: color.opacity(dark ? 0.16 : 0.10), location: 0),
                .init(color: color.opacity(dark ? 0.07 : 0.045), location: 0.42),
                .init(color: color.opacity(dark ? 0.02 : 0.015), location: 0.72),
                .init(color: .clear, location: 1),
            ],
            center: UnitPoint(x: 0.5, y: 0.58),
            startRadiusFraction: 0.08,
            endRadiusFraction: 1
        )
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .offset(y: 12)
        .blur(radius: 22)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
