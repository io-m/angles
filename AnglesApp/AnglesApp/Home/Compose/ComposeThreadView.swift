import SwiftUI

/// Top-down: the thought sits at the top and each new row goes below it. While the thread fits,
/// nothing scrolls and the rows already there do not move. Once it is taller, a row arriving
/// scrolls the end into view (`ThreadFollow`). It runs under the header and the bottom bar and
/// dissolves there (`ComposeThreadMask`).
struct ComposeThreadView: View {
    // Flags last, so the value has no padding inside and an unchanged thread compares equal.
    let session: ComposeSession
    let edges: ComposeEdges
    let focus: ComposeFocus
    let follow: ThreadFollowBox
    var identityStore: ProfileIdentityStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isOnboardingTaste: Bool
    var isCelebratingSave: Bool

    private static let endID = "thread-end"

    var body: some View {
        let rows = ComposeThreadRow.rows(
            statement: session.statement,
            turns: session.turns,
            phase: session.phase,
            generation: session.liveGenerationID,
            fadeOnlyIDs: session.fadeOnlyRowIDs
        )
        let archiveIDs = session.archives.map(\.threadID)
        let ids = archiveIDs + rows.map(\.id)

        GeometryReader { window in
            let viewportHeight = window.size.height
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // No stack spacing: a collapsing archive or generation takes its gap
                        // with it, so nothing snaps when the animation ends.
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(session.archives) { generation in
                                ComposeArchiveSection(
                                    generation: generation,
                                    session: session,
                                    identityStore: identityStore
                                )
                                .padding(.bottom, ComposeLayout.rowSpacing)
                                .id(generation.threadID)
                                .transition(ComposeLayout.archiveTransition(reduceMotion: reduceMotion))
                            }

                            VStack(alignment: .leading, spacing: ComposeLayout.rowSpacing) {
                                ForEach(rows) { row in
                                    ComposeThreadRowView(
                                        row: row,
                                        session: session,
                                        focus: focus,
                                        identityStore: identityStore,
                                        isOnboardingTaste: isOnboardingTaste,
                                        isCelebratingSave: isCelebratingSave
                                    )
                                }
                            }
                            .id(session.liveGenerationID)
                            .transition(ComposeLayout.generationTransition(reduceMotion: reduceMotion))

                            Color.clear.frame(height: 0).id(Self.endID)
                        }
                        .transaction(value: ids) { transaction in
                            transaction.animation = reduceMotion ? nil : ComposeLayout.insertAnimation
                            transaction.addAnimationCompletion {
                                follow.state.arrivalSettled()
                            }
                        }

                        // The thread runs under the bar; its last row stops above the bar and its fade.
                        ComposeThreadTail(edges: edges)
                    }
                    .padding(.horizontal, ComposeLayout.edgePad)
                    .padding(.top, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight in
                        follow.naturalHeight = naturalHeight
                        contentHeightChanged(proxy, viewportHeight: viewportHeight)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewportHeight,
                        alignment: .topLeading
                    )
                }
                .defaultScrollAnchor(.top)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .modifier(ScrollSignalsFromiOS18(
                    onUserScroll: { follow.state.userScrolled() }
                ))
                .onChange(of: ids) { old, new in
                    if follow.state.rowsChanged(from: old, to: new) {
                        scrollIfOverflowing(proxy, viewportHeight: viewportHeight)
                    }
                }
            }
        }
    }

    private func contentHeightChanged(_ proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard follow.state.contentHeightChanged() else {
            return
        }
        scrollIfOverflowing(proxy, viewportHeight: viewportHeight)
        // Without animation there is no arrival to wait for: the first layout is the final one.
        if reduceMotion {
            follow.state.arrivalSettled()
        }
    }

    /// Only scrolls when the thread is actually taller than the window. While the thread fits,
    /// calling `scrollTo(..., anchor: .bottom)` fights `.defaultScrollAnchor(.top)` and the
    /// keyboard animation, causing visible vertical jitter.
    private func scrollIfOverflowing(_ proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard follow.naturalHeight > viewportHeight + 2, !follow.scrollScheduled else {
            return
        }
        follow.scrollScheduled = true
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.28)
        DispatchQueue.main.async {
            follow.scrollScheduled = false
            guard follow.naturalHeight > viewportHeight + 2 else {
                return
            }
            withAnimation(animation) {
                proxy.scrollTo(Self.endID, anchor: .bottom)
            }
        }
    }
}

/// The follow state lives outside SwiftUI's state, so updating it never redraws the thread.
@MainActor
final class ThreadFollowBox {
    var state = ThreadFollow()
    var naturalHeight: CGFloat = 0
    var scrollScheduled = false
}

/// Room under the last row for the bar and its fade. It reads the bar height itself, so the
/// input growing a line redraws only this spacer.
private struct ComposeThreadTail: View {
    let edges: ComposeEdges

    var body: some View {
        Color.clear
            .frame(height: edges.barHeight + ThreadMaskStops.bottomFade + 8)
    }
}

/// From iOS 18 the scroll view reports when the user takes it.
private struct ScrollSignalsFromiOS18: ViewModifier {
    let onUserScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting {
                        onUserScroll()
                    }
                }
        } else {
            content
        }
    }
}
