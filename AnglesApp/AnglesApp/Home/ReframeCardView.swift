import SwiftUI

struct ReframeCardView: View {
    let card: HomeCard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 226
    @State private var isFlipped = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var styleAppearance: CardStyleAppearance {
        CardStyleAppearance(style: card.result.style)
    }

    var body: some View {
        Button(action: flip) {
            FlipStack(progress: isFlipped ? 1 : 0) {
                frontFace
            } back: {
                backFace
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(CardFlipButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isFlipped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isFlipped
                ? "\(card.result.style.displayName) reframe. \(card.result.reframe)"
                : "\(card.result.style.displayName). \(card.thought)"
        )
        .accessibilityHint(isFlipped ? "Shows the original thought" : "Shows the reframe")
    }

    private var frontFace: some View {
        cardFace(background: frontSurface) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    iconBadge(
                        systemName: styleAppearance.systemImage,
                        color: styleAppearance.ink
                    )

                    Spacer(minLength: 4)

                    styleChip
                }

                Text(card.thought)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var backFace: some View {
        cardFace(background: backSurface) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    iconBadge(
                        systemName: "quote.opening",
                        color: styleAppearance.ink
                    )

                    Spacer(minLength: 4)

                    styleChip
                }

                Text(card.result.reframe)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(styleAppearance.ink.opacity(0.09), lineWidth: 1)
        }
    }

    private var styleChip: some View {
        Text(card.result.style.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(styleAppearance.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(styleAppearance.ink.opacity(0.14), in: Capsule())
    }

    private var frontSurface: Color {
        theme.surface
    }

    private var backSurface: LinearGradient {
        LinearGradient(
            colors: [styleAppearance.washHighlight, styleAppearance.wash],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconBadge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(
                color.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func cardFace<Background: ShapeStyle, Content: View>(
        background: Background,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func flip() {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isFlipped.toggle()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)) {
            isFlipped.toggle()
        }
    }
}

private struct CardFlipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct FlipStack<Front: View, Back: View>: View, Animatable {
    var progress: CGFloat
    var front: Front
    var back: Back

    init(
        progress: CGFloat,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.progress = progress
        self.front = front()
        self.back = back()
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showingBack = progress > 0.5

        ZStack {
            front
                .compositingGroup()
                .opacity(showingBack ? 0 : 1)

            back
                .compositingGroup()
                .scaleEffect(x: -1, y: 1)
                .opacity(showingBack ? 1 : 0)
        }
        .rotation3DEffect(
            .radians(Double(progress) * .pi),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
    }
}
