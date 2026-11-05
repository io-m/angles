import SwiftUI

/// Keeps the app dark and applies the saved accent, including sheets.
struct UserAppearance: ViewModifier {
    @ObservedObject var store: ThemeStore

    func body(content: Content) -> some View {
        let palette = AccentPalette(from: store.accentHSB, colorScheme: .dark)
        content
            .preferredColorScheme(.dark)
            .environment(\.accentPalette, palette)
            .environmentObject(store)
            .tint(palette.accent)
    }
}
