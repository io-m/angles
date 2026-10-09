import SwiftUI

/// Whether the input should hold the keyboard. The sheet and the session effects write it; only
/// the bottom bar reads it in a body, so a focus change redraws the bar alone.
@Observable
final class ComposeFocus {
    var isFocused = false
}

/// The input pill: the field, an optional note, the keyboard-dismiss button, and Send. Typing
/// redraws this view alone, never the thread. Its focus is owned by the bottom bar, which stays
/// when the input goes, so the keyboard leaves in the same update as a send.
struct ComposeInputBar: View {
    @Bindable var session: ComposeSession
    var fieldFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let note = session.bottomNote
        VStack(alignment: .leading, spacing: 0) {
            // The note lives inside the pill, on its opaque fill, so it can never be read
            // through the thread scrolling behind it.
            if let note {
                Text(note)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .accessibilityLabel(note)
                    .accessibilityIdentifier("compose.note")
                    .transition(.opacity)
            }

            HStack(alignment: .center, spacing: 0) {
                TextField(
                    session.openTurn == nil ? "Tell me what's on your mind..." : "Your answer...",
                    text: $session.composeText,
                    axis: .vertical
                )
                .font(.body.weight(.medium))
                .foregroundStyle(theme.ink)
                .textInputAutocapitalization(.sentences)
                .focused(fieldFocused)
                .accessibilityIdentifier("compose.input")
                .lineLimit(1...4)
                .frame(minHeight: 28, alignment: .leading)
                .padding(.leading, 18)
                .padding(.vertical, note == nil ? 16 : 10)

                trailingControls
            }
            .frame(minHeight: 56)
        }
        .background(
            fill,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 0.5)
        }
        .shadow(color: theme.shadowSoft, radius: 2, y: 1)
        .shadow(
            color: theme.shadowLift,
            radius: colorScheme == .dark ? 18 : 10,
            y: colorScheme == .dark ? 0 : 4
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Dark keyboard chrome is near #2B2B2A; keep the field in that family so they read as one slab.
    private var fill: Color {
        if colorScheme == .dark {
            return Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2A / 255)
        }
        return theme.surface
    }

    private var trailingControls: some View {
        HStack(spacing: 0) {
            if fieldFocused.wrappedValue {
                Button {
                    fieldFocused.wrappedValue = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }

            Button {
                // In the same update as the send, so the keyboard leaves with the field instead of
                // waiting for the bar's fade-out to finish.
                if session.canSubmit {
                    fieldFocused.wrappedValue = false
                }
                onSubmit()
            } label: {
                CircleIcon(
                    systemName: "arrow.up",
                    fill: theme.ink,
                    symbol: theme.paper,
                    weight: .semibold
                )
            }
            .buttonStyle(.plain)
            .disabled(!session.canSubmit)
            .opacity(session.canSubmit ? 1 : 0.35)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("compose.send")
        }
        .padding(8)
    }
}

extension ComposeSession {
    /// One short line inside the input (or on a chip above the bottom button): a failed save
    /// or a send that was refused.
    var bottomNote: String? {
        saveError ?? composeNote
    }
}
