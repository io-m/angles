import SwiftUI

/// People the viewer follows. Same sheet chrome as Settings; rows follow the filter list.
struct FollowingSheet: View {
    let people: [FollowedPerson]
    let loadState: LibraryLoadState
    var onRetry: () -> Void
    var onUnfollow: (FollowedPerson) -> Void
    var onOpen: (FollowedPerson) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var filteredPeople: [FollowedPerson] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return people
        }
        return people.filter {
            displayInitials($0.initials).localizedStandardContains(needle)
        }
    }

    var body: some View {
        ModalScreen(title: "Following", searchText: $query) {
            Group {
                if !searching || !filteredPeople.isEmpty {
                    if people.isEmpty {
                        empty
                    } else {
                        list
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredPeople.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.leading, 70)
                }
                personRow(person)
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var empty: some View {
        VStack(spacing: 12) {
            switch loadState {
            case .loading:
                ProgressView()
                    .tint(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 88)
            case .failed(let message):
                Text(message)
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                Button("Try again", action: onRetry)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
            case .loaded:
                Text("You aren't following anyone yet.")
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .padding(20)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func personRow(_ person: FollowedPerson) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpen(person)
            } label: {
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

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayInitials(person.initials))
            .accessibilityHint("Opens their posts")

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onUnfollow(person)
            } label: {
                Image(systemName: "person.badge.minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unfollow \(displayInitials(person.initials))")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    private func displayInitials(_ initials: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Y" : trimmed
    }
}
