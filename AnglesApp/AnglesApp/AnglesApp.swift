import SwiftUI

@main
struct AnglesApp: App {
    @State private var navigationPath: [DrawerDestination] = []

    var body: some Scene {
        WindowGroup {
            GeometryReader { geometry in
                ZStack {
                    Color.anglesCanvasTop
                        .ignoresSafeArea()

                    NavigationStack(path: $navigationPath) {
                        HomeView(safeAreaInsets: geometry.safeAreaInsets) { destination in
                            navigationPath.append(destination)
                        }
                        .ignoresSafeArea(.container, edges: .vertical)
                        .navigationDestination(for: DrawerDestination.self) { destination in
                            DrawerStubView(destination: destination)
                        }
                    }
                    .background(Color.clear)
                }
                .tint(.anglesAccent)
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}
