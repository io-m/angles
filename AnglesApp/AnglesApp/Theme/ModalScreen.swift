import SwiftUI

/// Sheet chrome: large title that collapses to a centered inline title, gradient top instead of a solid bar.
struct ModalScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .background(theme.grey.ignoresSafeArea())
        }
        .tint(theme.ink)
        .background(theme.grey.ignoresSafeArea())
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: theme.grey.opacity(0.94), location: 0),
                    .init(color: theme.grey.opacity(0.52), location: 0.48),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}
