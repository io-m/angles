import SwiftUI

/// The input until angles are on screen, then Post anchored here (the taste's Save bar is the
/// same bar). While the angles are written the bar's place is held empty.
struct ComposeBottomBar: View {
    let session: ComposeSession
    let edges: ComposeEdges
    let focus: ComposeFocus
    var isOnboardingTaste: Bool
    var isCelebratingSave: Bool
    var onSubmit: () -> Void
    var onPost: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let mode = ComposeBottomMode(phase: session.phase)
        let note = session.bottomNote
        VStack(spacing: 0) {
            if mode == .composer {
                ComposeInputBar(session: session, fieldFocused: $fieldFocused, onSubmit: onSubmit)
                    .transition(.opacity)
            } else if mode == .post {
                if let note {
                    ComposeNoteChip(note: note)
                        .transition(.opacity)
                }
                ComposePostBar(
                    session: session,
                    isOnboardingTaste: isOnboardingTaste,
                    isCelebratingSave: isCelebratingSave,
                    onPost: onPost
                )
                .transition(.opacity)
            } else {
                // Holds the bar's place, so the thread's window never changes size.
                Color.clear
                    .frame(height: ComposeLayout.bottomBarHeight)
                    .accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
            // The thread's fade line: moves with the keyboard and with the input growing.
            edges.bottom = minY
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if height > 0, edges.barHeight != height {
                edges.barHeight = height
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: mode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: note)
        .onAppear {
            fieldFocused = focus.isFocused
        }
        .onChange(of: focus.isFocused) { _, wanted in
            if fieldFocused != wanted {
                fieldFocused = wanted
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            if focus.isFocused != focused {
                focus.isFocused = focused
            }
        }
    }
}
