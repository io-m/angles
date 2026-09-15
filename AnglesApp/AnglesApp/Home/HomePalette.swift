import SwiftUI
import UIKit

/// Soft, symmetric ambient lift for cards in a vertical list.
enum ReframeCardElevation {
    private static let wideRadiusDark: CGFloat = 22
    private static let wideRadiusLight: CGFloat = 26

    /// Room for the halo so horizontal strips do not clip top/bottom.
    static func ambientPadding(isDark: Bool) -> CGFloat {
        (isDark ? wideRadiusDark : wideRadiusLight) + 6
    }

    static func chrome<S: InsettableShape>(
        on content: some View,
        theme: ColorTokens.Theme,
        shape: S
    ) -> some View {
        let wideRadius: CGFloat = theme.isDark ? wideRadiusDark : wideRadiusLight
        let coreRadius: CGFloat = theme.isDark ? 11 : 13

        return content
            .overlay {
                shape.strokeBorder(theme.cardHairline, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            .shadow(color: theme.cardAmbientShadow, radius: wideRadius, x: 0, y: 0)
            .shadow(color: theme.cardAmbientCore, radius: coreRadius, x: 0, y: 0)
    }
}

struct ReframeCardElevationModifier<S: InsettableShape>: ViewModifier {
    let theme: ColorTokens.Theme
    let shape: S

    func body(content: Content) -> some View {
        ReframeCardElevation.chrome(on: content, theme: theme, shape: shape)
    }
}

struct AnglesCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        LinearGradient(
            colors: [theme.paper, theme.grey],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct CardStyleAppearance {
    let style: Style
    let systemImage: String
    /// Chips, pills, and icon accents.
    let ink: Color
    /// Reframe answer copy — tinted by style, tuned for the card wash.
    let responseInk: Color

    init(style: Style) {
        self.style = style
        // Four hue families spaced on the wheel so chips and washes never blur together:
        // stoic = cool slate-blue, optimistic = amber, humorous = jade, tough_love = brick.
        switch style {
        case .stoic:
            systemImage = "mountain.2.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.18, green: 0.37, blue: 0.47, alpha: 1),
                dark: UIColor(red: 0.47, green: 0.66, blue: 0.78, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.11, green: 0.27, blue: 0.34, alpha: 1),
                dark: UIColor(red: 0.82, green: 0.89, blue: 0.93, alpha: 1)
            )
        case .optimistic:
            systemImage = "sun.max.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.71, green: 0.47, blue: 0.08, alpha: 1),
                dark: UIColor(red: 0.88, green: 0.71, blue: 0.34, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.47, green: 0.31, blue: 0.05, alpha: 1),
                dark: UIColor(red: 0.94, green: 0.86, blue: 0.70, alpha: 1)
            )
        case .humorous:
            systemImage = "theatermasks.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.09, green: 0.51, blue: 0.40, alpha: 1),
                dark: UIColor(red: 0.28, green: 0.78, blue: 0.63, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.05, green: 0.35, blue: 0.27, alpha: 1),
                dark: UIColor(red: 0.78, green: 0.94, blue: 0.88, alpha: 1)
            )
        case .toughLove:
            systemImage = "flame.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.73, green: 0.23, blue: 0.19, alpha: 1),
                dark: UIColor(red: 0.91, green: 0.55, blue: 0.43, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.47, green: 0.13, blue: 0.11, alpha: 1),
                dark: UIColor(red: 0.96, green: 0.84, blue: 0.80, alpha: 1)
            )
        }
    }

    /// Selected pill background — tinted but still quieter than the answer copy.
    func chipFillOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.16 : 0.22
    }

    func chipUnselectedFillOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.13 : 0.16
    }

    func chipUnselectedInkOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.78 : 0.62
    }

    func washOpacityStops(for scheme: ColorScheme) -> (top: Double, mid: Double, bottom: Double) {
        StyleWashStrength.card.opacityStops(for: scheme)
    }

    /// Top-left fades out; color collects toward the bottom-right. Light from -45°.
    func washFill(over surface: Color) -> some View {
        StyleWashFill(ink: ink, surface: surface, strength: .card)
    }

    func headerWashFill(over surface: Color) -> some View {
        StyleWashFill(ink: ink, surface: surface, strength: .header)
    }
}

enum StyleWashStrength {
    case card
    case header

    func opacityStops(for scheme: ColorScheme) -> (top: Double, mid: Double, bottom: Double) {
        switch self {
        case .card:
            if scheme == .dark {
                return (0.025, 0.06, 0.12)
            }
            return (0.028, 0.058, 0.112)
        case .header:
            if scheme == .dark {
                return (0.08, 0.16, 0.26)
            }
            return (0.09, 0.17, 0.28)
        }
    }
}

enum StyleWash {
    /// Opaque surface with a header-strength tint.
    static func headerFill(ink: Color, over surface: Color) -> some View {
        StyleWashFill(ink: ink, surface: surface, strength: .header)
    }

    /// One material plane whose positional tint follows horizontal pager progress.
    static func headerGlassFill(
        fromInk: Color,
        toInk: Color,
        progress: CGFloat
    ) -> some View {
        HeaderGlassFill(
            fromInk: fromInk,
            toInk: toInk,
            progress: progress
        )
    }
}

private struct HeaderGlassFill: View {
    let fromInk: Color
    let toInk: Color
    let progress: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let amount = min(1, max(0, progress))
        let tintOpacity = colorScheme == .dark ? 0.15 : 0.10
        let sheenOpacity = colorScheme == .dark ? 0.08 : 0.14

        ZStack {
            if reduceTransparency {
                theme.paper
            } else {
                Rectangle().fill(.thinMaterial)
            }

            fromInk.opacity(tintOpacity * (1 - amount))
            toInk.opacity(tintOpacity * amount)

            LinearGradient(
                colors: [
                    .white.opacity(sheenOpacity),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .accessibilityHidden(true)
    }
}

struct StyleWashFill: View {
    let ink: Color
    let surface: Color
    var strength: StyleWashStrength = .card
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        surface.overlay(StyleWashTint(ink: ink, strength: strength))
    }
}

private struct StyleWashTint: View {
    let ink: Color
    let strength: StyleWashStrength

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let stops = strength.opacityStops(for: colorScheme)

        LinearGradient(
            stops: [
                .init(color: ink.opacity(stops.top), location: 0),
                .init(color: ink.opacity(stops.mid), location: 0.55),
                .init(color: ink.opacity(stops.bottom), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension Color {
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}
