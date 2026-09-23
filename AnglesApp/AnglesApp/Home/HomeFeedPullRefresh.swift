import SwiftUI

/// Pull-to-refresh on a full-bleed feed. The page keeps a clear chrome spacer
/// inside the scroll content so cards can pass behind the frosted header.
struct HomeFeedNativeRefresh: ViewModifier {
    let enabled: Bool
    let onRefresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .refreshable {
                guard enabled else {
                    return
                }
                await onRefresh()
            }
    }
}
