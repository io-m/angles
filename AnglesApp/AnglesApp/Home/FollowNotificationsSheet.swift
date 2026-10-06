import SwiftUI

/// People who followed you. Follow back uses the same follow write as an avatar.
struct FollowNotificationsSheet: View {
    let notices: [FollowNotice]
    let loadState: LibraryLoadState
    var onRetry: () -> Void
    var onFollowBack: (FollowNotice) -> Void
    var onOpen: (FollowNotice) -> Void
    var writeError: String? = nil
    var onDismissError: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        ModalScreen(title: "Follows") {
            Group {
                if notices.isEmpty {
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
            ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                if index > 0 {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.leading, 70)
                }
                noticeRow(notice)
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
                Text("Nothing yet.")
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .padding(20)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func noticeRow(_ notice: FollowNotice) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpen(notice)
            } label: {
                HStack(spacing: 14) {
                    AuthorMark(
                        initials: notice.initials,
                        avatarPath: notice.avatarPath,
                        side: 40,
                        fill: theme.ink,
                        symbol: theme.paper
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.publicLabel)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Text("\(notice.sentence) · \(Self.relative.localizedString(for: notice.createdAt, relativeTo: Date()))")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(notice.publicLabel) \(notice.sentence)")
            .accessibilityHint("Opens their posts")

            if notice.following {
                Text("Following")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFollowBack(notice)
                } label: {
                    Text("Follow back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Follow back \(notice.publicLabel)")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
    }

}
