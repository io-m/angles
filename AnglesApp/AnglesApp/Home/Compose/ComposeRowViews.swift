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
        let _ = RenderCounter.hit("ThreadRow \(row.kind.debugName)")
        switch row.kind {
        case .statement(let text):
            ComposeUserBubble(
                text: text,
                isFirst: true,
                identityStore: identityStore,
                showsEditCircle: !isOnboardingTaste,
                isEditEnabled: !session.isSessionBusy && session.hasCreditsForCook,
                isEditing: session.editingTarget == .statement,
                onEdit: {
                    if session.editingTarget == .statement {
                        session.cancelEdit()
                    } else {
                        session.beginEdit(.statement)
                    }
                }
            )
            .transition(arrival(from: .trailing))
        case .question(let turn):
            ComposeQuestionRow(turn: turn, session: session)
                .transition(arrival(from: .leading))
        case .reply(let turn):
            ComposeUserBubble(
                text: turn.reply ?? "",
                isFirst: false,
                identityStore: identityStore,
                showsEditCircle: !isOnboardingTaste,
                isEditEnabled: !session.isSessionBusy && session.hasCreditsForCook,
                isEditing: session.editingTarget == .reply(turn.id),
                onEdit: {
                    if session.editingTarget == .reply(turn.id) {
                        session.cancelEdit()
                    } else {
                        session.beginEdit(.reply(turn.id))
                    }
                }
            )
            .transition(arrival(from: .trailing))
        case .cooking:
            ComposeCookingRow()
                .transition(arrival(from: .leading))
        case .angles(let cook):
            ComposeAnglesRow(
                cook: cook,
                session: session,
                focus: focus,
                identityStore: identityStore,
                isOnboardingTaste: isOnboardingTaste,
                isCelebratingSave: isCelebratingSave
            )
            .transition(arrival(from: .leading))
        case .error(let message):
            ComposeErrorRow(message: message, session: session)
                .transition(arrival(from: .leading))
        }
    }

    private func arrival(from edge: HorizontalEdge) -> AnyTransition {
        if row.arrives {
            return ComposeLayout.arrival(from: edge, reduceMotion: reduceMotion)
        }
        return ComposeLayout.fadeArrival(reduceMotion: reduceMotion)
    }
}

/// Something the user wrote: one fill, on the right, as wide as its text. A permanent circular
/// edit button sits to the left of live bubbles so the row geometry never shifts across states.
struct ComposeUserBubble: View {
    let text: String
    let isFirst: Bool
    var identityStore: ProfileIdentityStore?
    var showsEditCircle: Bool = false
    var isEditEnabled: Bool = false
    var isEditing: Bool = false
    var isStale: Bool = false
    var onEdit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: showsEditCircle ? 12 : ComposeLayout.userSideGap)

            HStack(alignment: .center, spacing: 8) {
                if showsEditCircle, !isStale, let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isEditing ? theme.paper : theme.ink)
                            .frame(width: 34, height: 34)
                            .background(
                                isEditing ? theme.ink : theme.surface,
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        isEditing ? theme.ink : theme.line,
                                        lineWidth: 1
                                    )
                            }
                            .shadow(color: theme.shadowLift, radius: 5, y: 2)
                            .padding(.vertical, 5)
                            .padding(.leading, 6)
                            .contentShape(Rectangle())
                            .padding(.vertical, -5)
                            .padding(.leading, -6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditEnabled)
                    .opacity(isEditEnabled ? 1 : 0.35)
                    .accessibilityLabel(
                        isEditing
                            ? (isFirst ? "Cancel editing thought" : "Cancel editing answer")
                            : (isFirst ? "Edit thought" : "Edit answer")
                    )
                    .accessibilityIdentifier(
                        isFirst ? "compose.edit.thought" : "compose.edit.answer"
                    )
                }

                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.paper)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        isStale ? theme.ink.opacity(0.68) : theme.ink,
                        in: ComposeLayout.bubbleShape(isAI: false)
                    )
                    .contentShape(ComposeLayout.bubbleShape(isAI: false))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        if showsEditCircle, !isStale, isEditEnabled, let onEdit {
                            Button(action: onEdit) {
                                Label(
                                    isEditing ? "Cancel edit" : "Edit",
                                    systemImage: isEditing ? "xmark" : "pencil"
                                )
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(text)
                    .accessibilityIdentifier(isFirst ? "compose.thought" : "compose.answer")
            }

            ComposeUserAvatar(identityStore: identityStore)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A `continue` turn: what the AI said, plus inset rounded quick-reply pills inside the bubble
/// while it is unanswered.
struct ComposeQuestionRow: View {
    let turn: RefineTurn
    let session: ComposeSession
    var isStale: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var showsOptions: Bool {
        !isStale
            && !turn.safety.needsCare
            && !turn.isAnswered
            && !turn.options.isEmpty
            && session.editingTarget == nil
    }

    var body: some View {
        let shape = ComposeLayout.bubbleShape(isAI: true)
        HStack(alignment: .bottom, spacing: 10) {
            ComposeAIAvatar()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(turn.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isStale ? theme.muted : theme.ink)
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

                if showsOptions {
                    VStack(spacing: 8) {
                        ForEach(Array(turn.options.enumerated()), id: \.element) { index, option in
                            optionPill(option) {
                                session.chooseOption(option)
                            }
                            .accessibilityIdentifier("compose.option.\(index)")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface, in: shape)
            .overlay {
                shape.strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .shadow(color: theme.shadowSoft, radius: 6, y: 2)

            Spacer(minLength: ComposeLayout.aiSideGap)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(turn.message)
        .accessibilityIdentifier(turn.isAnswered ? "compose.answeredFollowup" : "compose.followup")
    }

    private func optionPill(_ title: String, action: @escaping () -> Void) -> some View {
        let pillShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let pillFill = colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.055)
        return Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(pillFill, in: pillShape)
                .contentShape(pillShape)
        }
        .buttonStyle(ComposeOptionPillButtonStyle(ink: theme.ink, shape: pillShape))
    }
}

private struct ComposeOptionPillButtonStyle: ButtonStyle {
    var ink: Color
    var shape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                shape.fill(ink.opacity(configuration.isPressed ? 0.06 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            Text(
                ComposeLeavePrompt.restartMessage(
                    isBusy: session.isSessionBusy,
                    hasArchives: !session.archives.isEmpty
                )
            )
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

/// Synchronously interpolates its child's height from 0 to 100% during expand/collapse so
/// sibling rows below move in lockstep on every frame with zero overlapping surfaces.
struct CollapsibleHeightLayout: Layout, Animatable {
    var progress: CGFloat
    /// The edge the child stays pinned to while the height is partial.
    var anchor: VerticalEdge = .top

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else {
            return .zero
        }
        let natural = subview.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil)
        )
        let clamped = min(max(progress, 0), 1)
        return CGSize(width: natural.width, height: natural.height * clamped)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else {
            return
        }
        let natural = subview.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        let pinnedToBottom = anchor == .bottom
        subview.place(
            at: CGPoint(x: bounds.minX, y: pinnedToBottom ? bounds.maxY : bounds.minY),
            anchor: pinnedToBottom ? .bottomLeading : .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

/// An exchange replaced by an edit: a stone accordion that expands to show the stale thread
/// and, when angles were written, the card with "Post this version".
struct ComposeArchiveSection: View {
    let generation: ComposeGeneration
    let session: ComposeSession
    var identityStore: ProfileIdentityStore?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bodyMounted = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var isExpanded: Bool { generation.isExpanded }
    private var isSavingThis: Bool {
        session.isSaving && session.savingArchiveID == generation.id
    }

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    /// A soft tint on the paper, same idea as dark mode — no boxed border.
    private var containerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var headerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.055)
    }

    private var insetDivider: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }

    /// Between a stale archive and the live thread below.
    private var liveThreadSeparator: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if bodyMounted || isExpanded {
                    CollapsibleHeightLayout(progress: isExpanded ? 1 : 0) {
                        expandedBody
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 14)
                            .opacity(isExpanded ? 1 : 0)
                    }
                    .clipped()
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
                }
            }
            .background(containerFill)
            .clipShape(Self.shape)

            if isExpanded {
                Rectangle()
                    .fill(liveThreadSeparator)
                    .frame(height: 1)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            bodyMounted = isExpanded
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                bodyMounted = true
            }
        }
        .transaction(value: isExpanded) { transaction in
            transaction.addAnimationCompletion {
                if !generation.isExpanded {
                    bodyMounted = false
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(generation.threadID)
    }

    private var header: some View {
        Button {
            withAnimation(ComposeLayout.collapse(reduceMotion)) {
                session.toggleArchiveExpanded(generation.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                            Text("Edited")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06),
                            in: Capsule()
                        )

                        Text("Previous version")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.sub)
                    }

                    Text(generation.statement)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.sub)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05),
                        in: Circle()
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isExpanded ? headerFill : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(insetDivider)
                    .frame(height: 1)
                    .opacity(isExpanded ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edited, previous version")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(
            generation.cook == nil
                ? "Shows the earlier thought and the question"
                : "Shows the earlier thought and its angles"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("compose.archive.header")
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: ComposeLayout.rowSpacing) {
            ComposeUserBubble(
                text: generation.statement,
                isFirst: true,
                identityStore: identityStore,
                isStale: true
            )
            .opacity(0.75)

            ForEach(generation.turns) { turn in
                ComposeQuestionRow(turn: turn, session: session, isStale: true)
                    .opacity(0.75)
                if let reply = turn.reply {
                    ComposeUserBubble(
                        text: reply,
                        isFirst: false,
                        identityStore: identityStore,
                        isStale: true
                    )
                    .opacity(0.75)
                }
            }

            if let cook = generation.cook {
                staleCard(cook)
                    .saturation(0.65)
                    .opacity(0.92)
                cookFooter
            } else {
                Text("This version stopped at a question.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.sub)
                    .padding(.leading, ComposeLayout.aiAvatarColumn)
                    .accessibilityIdentifier("compose.archive.noCard")
            }
        }
    }

    private var cookFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = generation.recookNotice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let feedback = generation.usageFeedback {
                Text(feedback)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.sub)
            }
            archivePostButton
            if let error = generation.saveError {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("compose.archive.saveError")
            }
        }
        .padding(.leading, ComposeLayout.aiAvatarColumn)
    }

    private func staleCard(_ cook: ReadyCook) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ComposeAIAvatar()

            OverlayProposalCard(
                thought: cook.thought,
                thoughtOriginal: cook.thoughtOriginal,
                results: cook.results.map(\.result),
                recookingStyle: nil,
                identityStore: identityStore,
                isPublic: archivePublic,
                showsPrivacyToggle: !generation.posted,
                allowsRecook: false
            )
            .accessibilityIdentifier("compose.archive.card")
        }
    }

    private var archivePublic: Binding<Bool> {
        Binding(
            get: {
                session.archives.first(where: { $0.id == generation.id })?.isPublic
                    ?? generation.isPublic
            },
            set: { session.setArchivePublic(generation.id, $0) }
        )
    }

    private var archivePostButton: some View {
        Button {
            Task { await session.saveArchive(generation.id) }
        } label: {
            HStack(spacing: 8) {
                if isSavingThis {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.paper)
                } else if generation.posted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(archivePostTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(theme.paper)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .background(theme.ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(generation.posted || session.isSaving)
        .opacity(generation.posted || session.isSaving ? 0.65 : 1)
        .accessibilityLabel(archivePostTitle)
        .accessibilityIdentifier("compose.archive.post")
    }

    private var archivePostTitle: String {
        if generation.posted {
            return generation.isPublic ? "Posted" : "Saved"
        }
        if isSavingThis {
            return "Saving"
        }
        return generation.isPublic ? "Post this version" : "Save this version privately"
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
