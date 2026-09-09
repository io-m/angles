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
    let wash: Color
    let washHighlight: Color

    init(style: Style) {
        switch style {
        case .stoic:
            systemImage = "mountain.2.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.32, green: 0.42, blue: 0.49, alpha: 1),
                dark: UIColor(red: 0.62, green: 0.71, blue: 0.77, alpha: 1)
            )
            washHighlight = Color.adaptive(
                light: UIColor(red: 0.967, green: 0.974, blue: 0.979, alpha: 1),
                dark: UIColor(red: 0.163, green: 0.177, blue: 0.193, alpha: 1)
            )
            wash = Color.adaptive(
                light: UIColor(red: 0.958, green: 0.967, blue: 0.974, alpha: 1),
                dark: UIColor(red: 0.145, green: 0.157, blue: 0.173, alpha: 1)
            )
        case .optimistic:
            systemImage = "sun.max.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.65, green: 0.43, blue: 0.09, alpha: 1),
                dark: UIColor(red: 0.94, green: 0.76, blue: 0.42, alpha: 1)
            )
            washHighlight = Color.adaptive(
                light: UIColor(red: 0.987, green: 0.979, blue: 0.959, alpha: 1),
                dark: UIColor(red: 0.198, green: 0.174, blue: 0.123, alpha: 1)
            )
            wash = Color.adaptive(
                light: UIColor(red: 0.976, green: 0.963, blue: 0.941, alpha: 1),
                dark: UIColor(red: 0.177, green: 0.151, blue: 0.103, alpha: 1)
            )
        case .humorous:
            systemImage = "face.smiling"
            ink = Color.adaptive(
                light: UIColor(red: 0.64, green: 0.32, blue: 0.43, alpha: 1),
                dark: UIColor(red: 0.91, green: 0.63, blue: 0.72, alpha: 1)
            )
            washHighlight = Color.adaptive(
                light: UIColor(red: 0.986, green: 0.969, blue: 0.975, alpha: 1),
                dark: UIColor(red: 0.198, green: 0.141, blue: 0.157, alpha: 1)
            )
            wash = Color.adaptive(
                light: UIColor(red: 0.975, green: 0.949, blue: 0.962, alpha: 1),
                dark: UIColor(red: 0.169, green: 0.116, blue: 0.131, alpha: 1)
            )
        case .toughLove:
            systemImage = "bolt.fill"
            ink = Color.adaptive(
                light: UIColor(red: 0.55, green: 0.27, blue: 0.31, alpha: 1),
                dark: UIColor(red: 0.89, green: 0.60, blue: 0.64, alpha: 1)
            )
            washHighlight = Color.adaptive(
                light: UIColor(red: 0.986, green: 0.970, blue: 0.972, alpha: 1),
                dark: UIColor(red: 0.196, green: 0.131, blue: 0.137, alpha: 1)
            )
            wash = Color.adaptive(
                light: UIColor(red: 0.975, green: 0.949, blue: 0.955, alpha: 1),
                dark: UIColor(red: 0.167, green: 0.106, blue: 0.111, alpha: 1)
            )
        }
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
