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
            phase: session.phase
        )
        let ids = rows.map(\.id)

        GeometryReader { window in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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

                            Color.clear.frame(height: 0).id(Self.endID)
                        }

                        // The thread runs under the bar; its last row stops above the bar and its fade.
                        ComposeThreadTail(edges: edges)
                    }
                    .padding(.horizontal, ComposeLayout.edgePad)
                    .padding(.top, 4)
                    .modifier(ContentHeightBeforeiOS18 {
                        contentHeightChanged(proxy)
                    })
                    .frame(
                        maxWidth: .infinity,
                        minHeight: window.size.height,
                        alignment: .topLeading
                    )
                    .transaction(value: ids) { transaction in
                        transaction.animation = reduceMotion ? nil : ComposeLayout.insertAnimation
                        transaction.addAnimationCompletion {
                            follow.state.arrivalSettled()
                        }
                    }
                }
                .defaultScrollAnchor(.top)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .modifier(ScrollSignalsFromiOS18(
                    onContentHeight: { contentHeightChanged(proxy) },
                    onUserScroll: { follow.state.userScrolled() }
                ))
                .onChange(of: ids) { old, new in
                    scroll(follow.state.rowsChanged(from: old, to: new), proxy)
                }
            }
        }
    }

    private func contentHeightChanged(_ proxy: ScrollViewProxy) {
        guard follow.state.contentHeightChanged() else {
            return
        }
        scroll(true, proxy)
        // Without animation there is no arrival to wait for: the first layout is the final one.
        if reduceMotion {
            follow.state.arrivalSettled()
        }
    }

    /// Every follow scroll uses the same ease, and starts on the next turn of the main queue, after
    /// the new row's layout has been committed. Started in the same update, its first frames would
    /// be lost to that layout (the card's is heavy) and the scroll would read as a jump.
    private func scroll(_ toEnd: Bool, _ proxy: ScrollViewProxy) {
        guard toEnd else {
            return
        }
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.3)
        DispatchQueue.main.async {
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

/// iOS 17 has no scroll geometry: the content reports its own height.
private struct ContentHeightBeforeiOS18: ViewModifier {
    let onChange: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
        } else {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                onChange()
            }
        }
    }
}

/// From iOS 18 the scroll view reports its content height and when the user takes it.
private struct ScrollSignalsFromiOS18: ViewModifier {
    let onContentHeight: () -> Void
    let onUserScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                    onContentHeight()
                }
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
