import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    themeStore.appearanceMode = mode
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        CircleIcon(
                            systemName: symbol(for: mode),
                            fill: theme.grey,
                            symbol: theme.faint
                        )

                        Text(mode.title)
                            .font(.body)
                            .foregroundStyle(theme.ink)

                        Spacer(minLength: 16)

                        if themeStore.appearanceMode == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.ink)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    themeStore.appearanceMode == mode ? [.isSelected, .isButton] : .isButton
                )

                if mode != AppearanceMode.allCases.last {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.leading, 64)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 268)
        .background(theme.surface)
    }

    private func symbol(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
