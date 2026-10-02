import SwiftUI

/// Native pull-to-refresh for a feed page.
///
/// The closure passed to `.refreshable` must not branch on a Bool it captured.
/// SwiftUI keeps the first closure, and Home installs it before reveal, while
/// refresh is still disabled. A captured `false` shows the spinner and never
/// calls the server. Body writes the current flag and callback into `action`
/// on every pass; the closure reads that reference.
///
/// The fetch is not a child of the refreshable task. Publishing the shelf
/// cancels `.refreshable`, which would cancel a child before `URLSession`
/// sends. The work is detached, and the closure still waits for it, so the
/// spinner stays up until the result is applied. Home, the library, and an
/// author page all enter through here.
struct HomeFeedNativeRefresh: ViewModifier {
    let enabled: Bool
    let onRefresh: () async -> Void

    @State private var action = HomeFeedRefreshAction()

    func body(content: Content) -> some View {
        let action = action
        let _ = action.apply(enabled: enabled, run: onRefresh)
        content
            .refreshable {
                await action.perform()
            }
    }
}

/// Latest pull-to-refresh callback. A class so a closure SwiftUI froze on the
/// first layout still sees the flag from the latest body pass.
@MainActor
private final class HomeFeedRefreshAction {
    private var enabled = false
    private var run: () async -> Void = {}

    func apply(enabled: Bool, run: @escaping () async -> Void) {
        self.enabled = enabled
        self.run = run
    }

    func perform() async {
        guard enabled else {
            return
        }
        let work = Task.detached { @MainActor [self] in
            await self.run()
        }
        await work.value
    }
}
