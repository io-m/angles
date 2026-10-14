import SwiftUI

/// The cook haptic and the keyboard rules that follow the session's phase. It draws nothing and
/// is the only part of the sheet that reads the phase for them, so a phase change redraws this
/// empty view instead of the whole screen.
struct ComposeSessionEffects: View {
    let session: ComposeSession
    let focus: ComposeFocus
    var isActive: Bool

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(weight: .light), trigger: session.cookHaptic)
            .onAppear {
                focus.isFocused = isActive && session.phase == .composing
            }
            .onChange(of: session.phase) { _, newPhase in
                if isActive, newPhase == .composing || newPhase == .awaitingReply {
                    focus.isFocused = true
                }
                // New angles arrive with the keyboard down, so it never sits over a new card.
                if case .ready = newPhase, session.editingTarget == nil {
                    focus.isFocused = false
                }
            }
            .onChange(of: session.editingTarget) { _, target in
                guard isActive else {
                    return
                }
                if target != nil {
                    focus.isFocused = true
                } else if case .ready = session.phase {
                    focus.isFocused = false
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
