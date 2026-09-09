import SwiftUI

struct ReframeCardView: View {
    let card: HomeCard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 226
    @State private var isFlipped = false

    private var styleAppearance: CardStyleAppearance {
        CardStyleAppearance(style: card.result.style)
    }

    var body: some View {
        Button(action: flip) {
            Group {
                if reduceMotion {
                    if isFlipped {
                        backFace
                    } else {
                        frontFace
                    }
                } else {
                    frontFace.modifier(
                        FlipEffect(
                            progress: isFlipped ? 1 : 0,
                            back: backFace
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(.primary)
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
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .anglesSurface
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
        } else {
            withAnimation(.smooth(duration: 0.48)) {
                isFlipped.toggle()
            }
        }
    }
}

private struct FlipEffect<Back: View>: AnimatableModifier {
    var progress: Double
    let back: Back

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(progress < 0.5 ? 1 : 0)

            back
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 1.0 / 800.0
                )
                .opacity(progress < 0.5 ? 0 : 1)
        }
        .rotation3DEffect(
            .degrees(progress * 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 1.0 / 800.0
        )
    }
}
