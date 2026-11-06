import SwiftUI

struct BlockedPeopleSheet: View {
    let people: [BlockedPerson]
    let loadState: LibraryLoadState
    var onRetry: () -> Void
    var onUnblock: (BlockedPerson) -> Void
    var writeError: String? = nil
    var onDismissError: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ModalScreen(title: "Blocked people") {
            Group {
                if people.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay {
            WriteErrorBanner(message: writeError, onDismiss: onDismissError)
                .padding(.top, 8)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
                    value: writeError
                )
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                personRow(person, showsDivider: index < people.count - 1)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            switch loadState {
            case .loading:
                ProgressView()
                    .tint(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .accessibilityLabel("Loading blocked people")
            case .failed(let message):
                Text(message)
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                Button("Try again", action: onRetry)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
            case .loaded:
                Text("You haven't blocked anyone.")
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .padding(.top, 12)
    }

    private func personRow(_ person: BlockedPerson, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AuthorMark(
                    initials: person.initials,
                    avatarPath: person.avatarPath,
                    side: 40,
                    fill: theme.ink,
                    symbol: theme.paper
                )

                Text(displayInitials(person.initials))
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onUnblock(person)
                } label: {
                    Text("Unblock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(theme.grey, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unblock \(displayInitials(person.initials))")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
    }

    private func displayInitials(_ initials: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Y" : trimmed
    }
}
