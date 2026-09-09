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
    let systemImage: String
    let ink: Color

    init(style: Style) {
        switch style {
        case .stoic:
            systemImage = "mountain.2.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.30, green: 0.44, blue: 0.52, alpha: 1),
                dark: UIColor(red: 0.64, green: 0.76, blue: 0.82, alpha: 1)
            )
        case .optimistic:
            systemImage = "sun.max.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.78, green: 0.52, blue: 0.08, alpha: 1),
                dark: UIColor(red: 0.96, green: 0.80, blue: 0.42, alpha: 1)
            )
        case .humorous:
            systemImage = "face.smiling"
            ink = Color.adaptive(
                light: UIColor(red: 0.56, green: 0.32, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.84, green: 0.70, blue: 0.96, alpha: 1)
            )
        case .toughLove:
            systemImage = "bolt.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.72, green: 0.28, blue: 0.16, alpha: 1),
                dark: UIColor(red: 0.96, green: 0.58, blue: 0.42, alpha: 1)
            )
        }
    }

    /// Top-left fades out; color collects toward the bottom-right.
    func washFill(over surface: Color) -> some View {
        StyleWashFill(ink: ink, surface: surface)
    }
}

private struct StyleWashFill: View {
    let ink: Color
    let surface: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let top = colorScheme == .dark ? 0.10 : 0.02
        let mid = colorScheme == .dark ? 0.24 : 0.05
        let bottom = colorScheme == .dark ? 0.42 : 0.10

        surface.overlay(
            LinearGradient(
                stops: [
                    .init(color: ink.opacity(top), location: 0),
                    .init(color: ink.opacity(mid), location: 0.55),
                    .init(color: ink.opacity(bottom), location: 1)
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
