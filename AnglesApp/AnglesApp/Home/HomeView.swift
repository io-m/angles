import SwiftUI

struct HomeView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let headerHeight: CGFloat = 44
        static let headerTopPad: CGFloat = 6
    }

    let safeAreaInsets: EdgeInsets

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showSettings = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var headerOverlayHeight: CGFloat {
        safeAreaInsets.top + Layout.headerTopPad + Layout.headerHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnglesCanvasBackground()

            headerChrome
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
        }
    }

    private var headerChrome: some View {
        ZStack(alignment: .top) {
            headerFade

            header
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, safeAreaInsets.top + Layout.headerTopPad)
        }
    }

    private var header: some View {
        ZStack {
            Text("Home")
                .font(.title.bold())
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer(minLength: 0)

                Button {
                    showSettings = true
                } label: {
                    CircleIcon(
                        systemName: "gearshape",
                        fill: theme.surface,
                        symbol: theme.ink,
                        hairline: theme.cardHairline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .frame(minHeight: Layout.headerHeight, alignment: .center)
    }

    private var headerFade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: theme.paper.opacity(1), location: 0),
                Gradient.Stop(color: theme.paper.opacity(0.88), location: 0.52),
                Gradient.Stop(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: headerOverlayHeight + 12)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    }
    .environmentObject(ThemeStore())
}
