import SwiftUI

@main
struct AnglesApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

struct AppRoot: View {
    @State private var navigationPath: [DrawerDestination] = []
    @StateObject private var viewModel = HomeViewModel()
    @State private var isComposePresented = false
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.anglesCanvasTop
                .ignoresSafeArea()

            NavigationStack(path: $navigationPath) {
                HomeView(
                    viewModel: viewModel,
                    safeAreaInsets: homeSafeAreaInsets,
                    isComposePresented: $isComposePresented
                ) { destination in
                    navigationPath.append(destination)
                }
                .ignoresSafeArea(.container, edges: .vertical)
                .navigationDestination(for: DrawerDestination.self) { destination in
                    DrawerStubView(destination: destination)
                }
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
        .tint(.anglesAccent)
    }
}
