import SwiftUI

/// A traveling border spark. A card uses the full lap and shadow; chat uses a quieter pass;
/// the Posted toast uses one fast lap around its capsule.
struct CardArrivalGlow<S: Shape>: View {
    enum Prominence {
        case home
        case subtle
        /// One quick lap on a capsule. Thin stroke, little bloom.
        case pill
    }

    let tint: Color
    var prominence: Prominence = .home
    let shape: S

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: CGFloat = 0
    @State private var rotation: Double = -90 // Start at top

    private var strokeWidth: CGFloat {
        switch prominence {
        case .home: 2
        case .subtle: 1.25
        case .pill: 1.5
        }
    }

    private var lapDuration: Double {
        switch prominence {
        case .home: 2
        case .subtle: 1.6
        case .pill: 0.7
        }
    }

    private var fadeInDuration: Double {
        switch prominence {
        case .home: 0.4
        case .subtle: 0.3
        case .pill: 0.15
        }
    }

    private var holdBeforeFade: Duration {
        switch prominence {
        case .home: .milliseconds(1200)
        case .subtle: .milliseconds(900)
        case .pill: .milliseconds(650)
        }
    }

    private var fadeOutDuration: Double {
        switch prominence {
        case .home: 0.6
        case .subtle: 0.5
        case .pill: 0.3
        }
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            ZStack {
                arrivalShadow

                Color.clear
                    .overlay {
                        Rectangle()
                            .fill(
                                AngularGradient(
                                    stops: sparkStops,
                                    center: .center,
                                    angle: .degrees(0)
                                )
                            )
                            .frame(width: 1200, height: 1200)
                            .rotationEffect(.degrees(rotation))
                    }
                    .mask {
                        shape.stroke(lineWidth: strokeWidth)
                    }
                    .blendMode(.plusLighter)
                    .opacity(level)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: fadeInDuration)) {
                    level = 1
                }
                withAnimation(.linear(duration: lapDuration)) {
                    rotation = 360
                }
            }
            .task {
                try? await Task.sleep(for: holdBeforeFade)
                guard !Task.isCancelled else {
                    return
                }
                withAnimation(.easeOut(duration: fadeOutDuration)) {
                    level = 0
                }
            }
        }
    }

    private var arrivalShadow: some View {
        shape
            .fill(Color.clear)
            .shadow(
                color: tint.opacity(tintShadowOpacity * level),
                radius: shadowRadius.tint,
                x: 0,
                y: shadowOffset
            )
            .shadow(
                color: Color.black.opacity(blackShadowOpacity * level),
                radius: shadowRadius.black,
                x: 0,
                y: shadowOffset * 0.75
            )
    }

    private var shadowRadius: (tint: CGFloat, black: CGFloat) {
        switch prominence {
        case .home: (24, 16)
        case .subtle: (12, 8)
        case .pill: (6, 4)
        }
    }

    private var shadowOffset: CGFloat {
        switch prominence {
        case .home: 8
        case .subtle: 4
        case .pill: 1
        }
    }

    private var tintShadowOpacity: Double {
        let dark = colorScheme == .dark
        switch prominence {
        case .home:
            return dark ? 0.4 : 0.2
        case .subtle:
            return dark ? 0.18 : 0.1
        case .pill:
            return dark ? 0.14 : 0.08
        }
    }

    private var blackShadowOpacity: Double {
        let dark = colorScheme == .dark
        switch prominence {
        case .home:
            return dark ? 0.3 : 0.1
        case .subtle:
            return dark ? 0.12 : 0.04
        case .pill:
            return dark ? 0.08 : 0.03
        }
    }

    private var sparkStops: [Gradient.Stop] {
        let dark = colorScheme == .dark
        let scale: Double = prominence == .subtle ? 0.5 : 1
        let head: Color = dark
            ? tint.opacity(0.9 * scale)
            : (prominence == .subtle ? Color.white.opacity(0.5) : .white)
        return [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: 0.50),
            .init(color: tint.opacity((dark ? 0.15 : 0.3) * scale), location: 0.75),
            .init(color: tint.opacity((dark ? 0.5 : 0.8) * scale), location: 0.95),
            .init(color: head, location: 0.99),
            .init(color: .clear, location: 1.0),
        ]
    }
}

extension CardArrivalGlow where S == RoundedRectangle {
    /// The card outline. Call sites that omit a shape keep this rounded rect.
    init(tint: Color, prominence: Prominence = .home) {
        self.init(
            tint: tint,
            prominence: prominence,
            shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}
