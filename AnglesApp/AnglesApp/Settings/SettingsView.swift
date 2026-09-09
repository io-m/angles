import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentPalette) private var accentPalette

    @State private var showAppearance = false
    @State private var showAccent = false
    @State private var showSubscription = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private let edgePad: CGFloat = 20

    var body: some View {
        ModalScreen(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                    .padding(.bottom, 28)

                VStack(spacing: 0) {
                    cardRow(
                        symbol: "circle.lefthalf.filled",
                        title: "Appearance",
                        subtitle: themeStore.appearanceMode.title
                    ) {
                        showAppearance = true
                    } trailing: {
                        EmptyView()
                    }
                    .popover(isPresented: $showAppearance, arrowEdge: .top) {
                        AppearanceView()
                            .presentationCompactAdaptation(.popover)
                            .modifier(UserAppearance(store: themeStore))
                    }

                    rowDivider

                    cardRow(
                        symbol: "drop.fill",
                        title: "Accent",
                        subtitle: "Highlight color"
                    ) {
                        showAccent = true
                    } trailing: {
                        Circle()
                            .fill(accentPalette.accent)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle().strokeBorder(theme.cardHairline, lineWidth: 0.5)
                            }
                            .accessibilityHidden(true)
                    }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    cardRow(
                        symbol: "creditcard",
                        title: "Subscription",
                        subtitle: "Active"
                    ) {
                        showSubscription = true
                    } trailing: {
                        EmptyView()
                    }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, edgePad)
        }
        .sheet(isPresented: $showAccent) {
            AccentPickerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
        }
        .sheet(isPresented: $showSubscription) {
            DrawerStubView(title: "Subscription")
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 12) {
            CircleIcon(
                systemName: "person.fill",
                fill: theme.ink,
                symbol: theme.paper,
                size: .big
            )
            .accessibilityLabel("Profile")

            Text("On this iPhone")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.line)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func cardRow<Trailing: View>(
        symbol: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CircleIcon(systemName: symbol, fill: theme.grey, symbol: theme.faint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.muted)
                }

                Spacer(minLength: 8)

                trailing()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
