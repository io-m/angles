import SwiftUI
import UIKit

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
        switch style {
        case .stoic:
            systemImage = "mountain.2.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.30, green: 0.44, blue: 0.52, alpha: 1),
                dark: UIColor(red: 0.56, green: 0.66, blue: 0.72, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.24, green: 0.36, blue: 0.43, alpha: 1),
                dark: UIColor(red: 0.82, green: 0.86, blue: 0.88, alpha: 1)
            )
        case .optimistic:
            systemImage = "sun.max.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.78, green: 0.52, blue: 0.08, alpha: 1),
                dark: UIColor(red: 0.78, green: 0.64, blue: 0.36, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.52, green: 0.34, blue: 0.06, alpha: 1),
                dark: UIColor(red: 0.86, green: 0.78, blue: 0.62, alpha: 1)
            )
        case .humorous:
            systemImage = "face.smiling"
            ink = Color.adaptive(
                light: UIColor(red: 0.56, green: 0.32, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.68, green: 0.56, blue: 0.76, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.42, green: 0.24, blue: 0.50, alpha: 1),
                dark: UIColor(red: 0.84, green: 0.78, blue: 0.86, alpha: 1)
            )
        case .toughLove:
            systemImage = "bolt.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.72, green: 0.28, blue: 0.16, alpha: 1),
                dark: UIColor(red: 0.78, green: 0.50, blue: 0.38, alpha: 1)
            )
            responseInk = Color.adaptive(
                light: UIColor(red: 0.48, green: 0.20, blue: 0.12, alpha: 1),
                dark: UIColor(red: 0.88, green: 0.72, blue: 0.66, alpha: 1)
            )
        }
    }

    func chipFillOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.09 : 0.15
    }

    func washOpacityStops(for scheme: ColorScheme) -> (top: Double, mid: Double, bottom: Double) {
        if scheme == .dark {
            return (0.025, 0.06, 0.12)
        }
        // Original was 0.02 / 0.05 / 0.10 — nudged up just a touch.
        return (0.028, 0.058, 0.112)
    }

    /// Top-left fades out; color collects toward the bottom-right.
    func washFill(over surface: Color) -> some View {
        StyleWashFill(appearance: self, surface: surface)
    }
}

private struct StyleWashFill: View {
    let appearance: CardStyleAppearance
    let surface: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let stops = appearance.washOpacityStops(for: colorScheme)

        surface.overlay(
            LinearGradient(
                stops: [
                    .init(color: appearance.ink.opacity(stops.top), location: 0),
                    .init(color: appearance.ink.opacity(stops.mid), location: 0.55),
                    .init(color: appearance.ink.opacity(stops.bottom), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
