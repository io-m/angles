import SwiftUI

@main
struct AnglesApp: App {
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .modifier(UserAppearance(store: themeStore))
        }
    }
}

struct AppRoot: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var isComposePresented = false
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            NavigationStack {
                HomeView(
                    viewModel: viewModel,
                    safeAreaInsets: homeSafeAreaInsets,
                    isComposePresented: $isComposePresented
                )
                .ignoresSafeArea(.container, edges: .vertical)
            }
            .background(Color.clear)
            .ignoresSafeArea(.keyboard)

            ComposeFrost()
                .opacity(isComposePresented ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .animation(ComposeMotion.fade(reduceMotion), value: isComposePresented)

            ComposeSheetView(
                viewModel: viewModel,
                isActive: isComposePresented,
                onClose: {
                    isComposePresented = false
                }
            )
            .opacity(isComposePresented ? 1 : 0)
            .animation(
                ComposeMotion.contentFade(reduceMotion, presented: isComposePresented),
                value: isComposePresented
            )
            .allowsHitTesting(isComposePresented)
            .accessibilityHidden(!isComposePresented)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        homeSafeAreaInsets = geo.safeAreaInsets
                    }
                    .onChange(of: geo.safeAreaInsets) { _, newInsets in
                        homeSafeAreaInsets = newInsets
                    }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
