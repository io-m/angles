import SwiftUI

/// Starts the native vertical ScrollView below Home's fixed chrome so the
/// system refresh control emerges directly beneath the style tabs.
struct HomeFeedNativeRefresh: ViewModifier {
    let headerHeight: CGFloat
    let enabled: Bool
    let onRefresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .padding(.top, headerHeight)
            .refreshable {
                guard enabled else {
                    return
                }
                await onRefresh()
            }
    }
}
