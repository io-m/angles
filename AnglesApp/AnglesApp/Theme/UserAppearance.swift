import SwiftUI

/// Applies saved appearance + accent to the whole tree, including sheets.
struct UserAppearance: ViewModifier {
    @ObservedObject var store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let override = store.appearanceMode.colorScheme
        let scheme = override ?? colorScheme
        let palette = AccentPalette(from: store.accentHSB, colorScheme: scheme)
        content
            .preferredColorScheme(override)
            .environment(\.accentPalette, palette)
            .environmentObject(store)
            .tint(palette.accent)
    }
}
