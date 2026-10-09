import SwiftUI

/// One row of the thread. It slides in from its own side when it is new and never animates out.
struct ComposeThreadRowView: View {
    let row: ComposeThreadRow
    let session: ComposeSession
    let focus: ComposeFocus
    var identityStore: ProfileIdentityStore?
    var isOnboardingTaste: Bool
    var isCelebratingSave: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = RenderCounter.hit("ThreadRow \(row.id.prefix(2))")
        switch row.kind {
        case .statement:
            ComposeUserBubble(text: session.statement, isFirst: true, identityStore: identityStore)
                .transition(ComposeLayout.arrival(from: .trailing, reduceMotion: reduceMotion))
        case .question(let turn):
            ComposeQuestionRow(turn: turn, session: session)
                .transition(ComposeLayout.arrival(from: .leading, reduceMotion: reduceMotion))
        case .reply(let turn):
            ComposeUserBubble(text: turn.reply ?? "", isFirst: false, identityStore: identityStore)
                .transition(ComposeLayout.arrival(from: .trailing, reduceMotion: reduceMotion))
        case .cooking:
            ComposeCookingRow()
                .transition(ComposeLayout.arrival(from: .leading, reduceMotion: reduceMotion))
        case .angles(let cook):
            ComposeAnglesRow(
                cook: cook,
                session: session,
                focus: focus,
                identityStore: identityStore,
                isOnboardingTaste: isOnboardingTaste,
                isCelebratingSave: isCelebratingSave
            )
            .transition(ComposeLayout.arrival(from: .leading, reduceMotion: reduceMotion))
        case .error(let message):
            ComposeErrorRow(message: message, session: session)
                .transition(ComposeLayout.arrival(from: .leading, reduceMotion: reduceMotion))
        }
    }
}

/// Something the user wrote: one fill, on the right, as wide as its text. Tapping does
/// nothing; long-press copies.
struct ComposeUserBubble: View {
    let text: String
    let isFirst: Bool
    var identityStore: ProfileIdentityStore?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: ComposeLayout.userSideGap)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.paper)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.ink, in: ComposeLayout.bubbleShape(isAI: false))
                .contentShape(ComposeLayout.bubbleShape(isAI: false))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityIdentifier(isFirst ? "compose.thought" : "compose.answer")

            ComposeUserAvatar(identityStore: identityStore)
                .padding(.leading, 10)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A `continue` turn: what the AI said, plus optional chips while it is unanswered.
struct ComposeQuestionRow: View {
    let turn: RefineTurn
    let session: ComposeSession

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ComposeAIAvatar()

                VStack(alignment: .leading, spacing: 8) {
                    Text(turn.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if turn.safety.needsCare {
                        Text(turn.crisisResource ?? SafetyFlag.unknownRegionCrisisLine)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("compose.crisis")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.surface, in: ComposeLayout.bubbleShape(isAI: true))
                .shadow(color: theme.shadowSoft, radius: 6, y: 2)

                Spacer(minLength: ComposeLayout.aiSideGap)
            }

            // Quick replies sit under the question, in line with the bubble, like in a chat.
            if !turn.safety.needsCare, !turn.isAnswered, !turn.options.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(turn.options.enumerated()), id: \.element) { index, option in
                        optionRow(option) {
                            session.chooseOption(option)
                        }
                        .accessibilityIdentifier("compose.option.\(index)")
                    }
                }
                .padding(.leading, ComposeLayout.aiAvatarColumn)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(turn.message)
        .accessibilityIdentifier(turn.isAnswered ? "compose.answeredFollowup" : "compose.followup")
    }

    private func optionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(theme.grey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ComposeCookingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ComposeAIAvatar()

            CookingLine(
                ink: theme.ink,
                muted: theme.muted,
                reduceMotion: reduceMotion
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.surface, in: ComposeLayout.bubbleShape(isAI: true))
            .shadow(color: theme.shadowSoft, radius: 6, y: 2)

            Spacer(minLength: ComposeLayout.aiSideGap)
        }
    }
}

struct ComposeErrorRow: View {
    let message: String
    let session: ComposeSession

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ComposeAIAvatar()

            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if session.composeErrorAllowsRetry {
                    Button("Retry", action: session.retryRefine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.surface, in: ComposeLayout.bubbleShape(isAI: true))
            .shadow(color: theme.shadowSoft, radius: 6, y: 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message)
            .accessibilityIdentifier("compose.error")

            Spacer(minLength: ComposeLayout.aiSideGap)
        }
    }
}

/// The one card, on the AI's side with its avatar at the tail, then a caption and a quiet
/// Start new under it. Post is not here: it stays anchored at the bottom of the screen.
struct ComposeAnglesRow: View {
    let cook: ReadyCook
    @Bindable var session: ComposeSession
    let focus: ComposeFocus
    var identityStore: ProfileIdentityStore?
    var isOnboardingTaste: Bool
    var isCelebratingSave: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var showRestartAlert = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ComposeAIAvatar()

                OverlayProposalCard(
                    thought: cook.thought,
                    thoughtOriginal: cook.thoughtOriginal,
                    results: cook.results.map(\.result),
                    recookingStyle: session.recookingStyle,
                    identityStore: identityStore,
                    isPublic: $session.composeIsPublic,
                    showsPrivacyToggle: !isOnboardingTaste,
                    allowsRecook: !isOnboardingTaste && session.hasCreditsForCook,
                    onRecook: { style in
                        session.recookStyle(style)
                    }
                )
                .accessibilityIdentifier("compose.card")
            }

            VStack(alignment: .leading, spacing: 6) {
                if let notice = session.recookNotice {
                    Text(notice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let feedback = session.usageFeedback {
                    Text(feedback)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .accessibilityLabel(feedback)
                }

                if !isOnboardingTaste {
                    Button {
                        showRestartAlert = true
                    } label: {
                        Text("Start new")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isSaving || isCelebratingSave)
                    .accessibilityHint("Wipes this session and starts a new thought")
                    .accessibilityIdentifier("compose.startNew")
                }
            }
            .padding(.leading, ComposeLayout.aiAvatarColumn)
        }
        .task {
            guard !isOnboardingTaste else {
                return
            }
            await SaveRide.preload(dark: colorScheme == .dark)
        }
        .alert("Start again?", isPresented: $showRestartAlert) {
            Button("Start again", role: .destructive) {
                session.resetCompose()
                focus.isFocused = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ComposeLeavePrompt.restartMessage(isBusy: session.isSessionBusy))
        }
    }
}

struct ComposeAIAvatar: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ColorTokens.theme(colorScheme)
        InspireMarkCircle(
            fill: theme.surface,
            hairline: theme.cardHairline
        )
        .accessibilityHidden(true)
    }
}

struct ComposeUserAvatar: View {
    var identityStore: ProfileIdentityStore?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ColorTokens.theme(colorScheme)
        AuthorMark(
            initials: identityStore?.avatarLetters ?? identityStore?.serverInitials ?? UserInitials.letters,
            avatarPath: identityStore?.avatarPath,
            prefersLocalPhoto: true,
            side: 40,
            fill: theme.ink,
            symbol: theme.paper
        )
        .accessibilityHidden(true)
    }
}

private struct CookingLine: View {
    var ink: Color
    var muted: Color
    var reduceMotion: Bool

    @State private var lineIndex = 0
    @State private var stillWorking = false

    private static let lines = [
        "Reading it",
        "Finding the sting",
        "Writing four angles",
        "Almost there",
        "Still working on it",
    ]
    /// The lines that cycle by themselves. The last one only appears when a cook runs long.
    private static let cyclingLines = 4
    private static let stillWorkingAfter: Duration = .seconds(8)

    private var stem: String {
        Self.lines[visibleLineIndex]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .opacity(index == visibleLineIndex ? 1 : 0)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ink)
        }
        .task {
            let started = ContinuousClock.now
            if !reduceMotion {
                await cycleLines()
            }
            // A cook can take 9 s or more. Say so, so a long wait never reads as frozen.
            try? await Task.sleep(until: started + Self.stillWorkingAfter, clock: .continuous)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                stillWorking = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stem)
        .accessibilityIdentifier("compose.cooking")
    }

    private var visibleLineIndex: Int {
        if stillWorking {
            return Self.lines.count - 1
        }
        return reduceMotion ? Self.lines.firstIndex(of: "Writing four angles") ?? 0 : lineIndex
    }

    private func cycleLines() async {
        while !Task.isCancelled, lineIndex < Self.cyclingLines - 1 {
            do {
                try await Task.sleep(for: .milliseconds(1400))
            } catch {
                break
            }
            withAnimation(.easeInOut(duration: 0.45)) {
                lineIndex += 1
            }
        }
    }
}
