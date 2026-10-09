import Foundation

/// One `kind: "continue"` turn from the API plus whatever the user sent back.
struct RefineTurn: Identifiable, Equatable {
    let id: UUID
    let message: String
    let options: [String]
    let safety: SafetyFlag
    var crisisResource: String? = nil
    var reply: String?
    var replyWasChip: Bool = false

    var isAnswered: Bool {
        reply != nil
    }
}

struct ReadyCook: Equatable {
    var thought: String
    var thoughtOriginal: String?
    var results: [SignedReframeResult]
    var meta: ReframeMeta
    /// Server signature over `thought`, `thoughtOriginal`, `model`, and `meta`; Save sends it back.
    var signature: String
    /// The writer the server routed to. Opaque here: Save echoes it and nothing shows it.
    var model: String
}

enum RefinePhase: Equatable {
    case composing
    case cooking
    /// The AI asked for more. The composer stays up.
    case awaitingReply
    case ready(ReadyCook)
    case error(String)
}

/// What the compose session needs from the rest of the app: the shared credit balance, the
/// library a save lands in, and the taste gate.
@MainActor
protocol ComposeSessionHost: AnyObject {
    var hasCreditsForCook: Bool { get }
    var usageStatus: String? { get }
    var usageIsCritical: Bool { get }
    var libraryCardCount: Int { get }
    func applyCookUsage(_ usage: ReframeUsage)
    func applyUsage(from payload: APIErrorPayload)
    func markTasteEnded()
    func insertSavedCard(_ card: HomeCard)
}

/// One thought being composed: what the user wrote, the AI's turns, the cook, and its save.
@MainActor
@Observable
final class ComposeSession {
    var composeText = "" {
        didSet {
            guard composeText != oldValue else {
                return
            }
            if composeNote != nil {
                composeNote = nil
            }
        }
    }
    /// A short reason the last Send did nothing (the thought is too long). Typing clears it.
    private(set) var composeNote: String?
    /// Compose Save defaults public; Start new and a new overlay reset this.
    var composeIsPublic = true
    /// What the user wrote about this thought, which is what the server reads (the first
    /// thought, plus extra context after an error). Never anything the AI wrote.
    private(set) var statement = ""
    private(set) var turns: [RefineTurn] = []
    private(set) var phase: RefinePhase = .composing
    private(set) var cookHaptic = 0
    private(set) var recookingStyle: Style?
    /// Set when a recook comes back as `continue` (that style no longer fits).
    private(set) var recookNotice: String?
    /// "1 credit used" under the card after a cook or recook.
    private(set) var usageFeedback: String?
    private(set) var composeErrorAllowsRetry = true
    private(set) var isSaving = false
    private(set) var saveError: String?

    @ObservationIgnored weak var host: ComposeSessionHost?
    @ObservationIgnored private let reframeService: ReframeService
    @ObservationIgnored private let cardsService: CardsService
    @ObservationIgnored private var refineTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<HomeCard?, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingRefineAttempt: ReframeAttempt?
    @ObservationIgnored private var pendingRecookAttempt: ReframeAttempt?
    @ObservationIgnored private var pendingRecookStyle: Style?

    /// The most the server reads as one thought (`MAX_TEXT_LENGTH` in `routes/reframe.ts`).
    static let maxThoughtLength = 2000
    /// The server accepts at most this many follow-ups (`MAX_FOLLOW_UPS`).
    private static let maxFollowUps = 6

    init(reframeService: ReframeService, cardsService: CardsService) {
        self.reframeService = reframeService
        self.cardsService = cardsService
    }

    /// False only once the server says the balance cannot pay for one more cook.
    var hasCreditsForCook: Bool {
        host?.hasCreditsForCook ?? true
    }

    var usageStatus: String? {
        host?.usageStatus
    }

    var usageIsCritical: Bool {
        host?.usageIsCritical ?? false
    }

    /// The composer is there until angles are on screen. A finished cook is one card; the only
    /// way on is Start new.
    var isComposerVisible: Bool {
        phase.showsComposer
    }

    var canSubmit: Bool {
        isComposerVisible
            && !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasCreditsForCook
            && !isSessionBusy
    }

    var canPublish: Bool {
        phase.hasPublishableCook
    }

    /// The card's Post waits while anything is writing or saving, so posting never closes the
    /// sheet on a running cook.
    var canPostCook: Bool {
        canPublish && !isSessionBusy
    }

    var isCookReady: Bool {
        if case .ready = phase {
            return true
        }
        return false
    }

    var isCooking: Bool {
        if case .cooking = phase {
            return true
        }
        return false
    }

    var isSessionBusy: Bool {
        isCooking || recookingStyle != nil || isSaving
    }

    var hasSessionWork: Bool {
        if isSessionBusy || !statement.isEmpty || !turns.isEmpty {
            return true
        }
        switch phase {
        case .ready, .error:
            return true
        case .composing, .awaitingReply, .cooking:
            return false
        }
    }

    var openTurn: RefineTurn? {
        turns.last(where: { !$0.isAnswered })
    }

    /// A crisis continue, or a cook whose safety is not `none`, blocks an App Store review.
    /// Anything other than a finished cook fails closed.
    var composeSessionNeedsCare: Bool {
        if turns.contains(where: { $0.safety.needsCare }) {
            return true
        }
        guard case .ready(let cook) = phase else {
            return true
        }
        return cook.meta.safety.needsCare
    }

    /// The user's own answers to the AI's questions. The server counts them toward its
    /// two-question limit, so a thought that has already been asked twice goes straight to
    /// a cook.
    private var answeredFollowUps: [FollowUpAnswer] {
        let answers = turns.compactMap { turn -> FollowUpAnswer? in
            guard let reply = turn.reply else {
                return nil
            }

            return FollowUpAnswer(question: turn.message, answer: reply)
        }
        return Array(answers.suffix(Self.maxFollowUps))
    }

    /// One entry point for the composer: the thought, a reply to a question, or extra context
    /// after an error. The field keeps its text when the send is refused.
    func sendComposer() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else {
            return
        }

        guard send(text, isChip: false) else {
            return
        }
        composeText = ""
    }

    func chooseOption(_ option: String) {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .awaitingReply = phase, !trimmed.isEmpty else {
            return
        }

        send(trimmed, isChip: true)
    }

    /// Returns false when nothing was sent.
    @discardableResult
    private func send(_ text: String, isChip: Bool) -> Bool {
        if statement.isEmpty {
            guard fits(text, startsFresh: true) else {
                return false
            }
            statement = text
            turns = []
        } else if let index = turns.lastIndex(where: { !$0.isAnswered }) {
            turns[index].reply = text
            turns[index].replyWasChip = isChip
        } else {
            let combined = "\(statement)\n\n\(text)"
            guard fits(combined, startsFresh: false) else {
                return false
            }
            statement = combined
        }

        composeNote = nil
        let attempt = ReframeAttempt()
        pendingRefineAttempt = attempt
        startRefine(attempt: attempt)
        return true
    }

    /// The server rejects a thought past `maxThoughtLength`; say so here instead of a 400.
    private func fits(_ writing: String, startsFresh: Bool) -> Bool {
        guard writing.utf16.count > Self.maxThoughtLength else {
            return true
        }
        composeNote = startsFresh
            ? "That’s too long for one thought. Shorten it and send again."
            : "That’s a lot for one thought. Start again to write a new one."
        return false
    }

    func retryRefine() {
        guard case .error = phase, !statement.isEmpty, composeErrorAllowsRetry else {
            return
        }

        let attempt = pendingRefineAttempt ?? ReframeAttempt()
        pendingRefineAttempt = attempt
        startRefine(attempt: attempt)
    }

    /// `forcePrivate` is the onboarding taste: that save is private whatever the toggle says.
    func saveCook(forcePrivate: Bool = false) async -> HomeCard? {
        guard case .ready(let cook) = phase else {
            return nil
        }
        let wantsPublic = composeIsPublic
        guard !cook.results.isEmpty, !isSaving else {
            return nil
        }

        isSaving = true
        saveError = nil
        let styles = cook.results.map(\.style)
        let spotlight = styles[(host?.libraryCardCount ?? 0) % styles.count]
        let isPublic = forcePrivate ? false : wantsPublic
        let task = Task<HomeCard?, Never> { @MainActor in
            do {
                let stored = try await cardsService.create(
                    CreateCardRequest(
                        thought: cook.thought,
                        thoughtOriginal: cook.thoughtOriginal,
                        results: cook.results,
                        meta: cook.meta,
                        signature: cook.signature,
                        model: cook.model,
                        spotlightStyle: spotlight,
                        isPublic: isPublic
                    )
                )
                guard !Task.isCancelled else {
                    isSaving = false
                    return nil
                }
                guard let card = HomeCard(stored: stored) else {
                    isSaving = false
                    saveError = "Saved, but couldn't display this card."
                    return nil
                }
                host?.insertSavedCard(card)
                isSaving = false
                return card
            } catch {
                isSaving = false
                guard !Task.isCancelled, !HomeViewModel.isCancellation(error) else {
                    return nil
                }
                saveError = HomeViewModel.publicModerationMessage(for: error)
                    ?? "Couldn't save this card. Try again."
                return nil
            }
        }
        saveTask = task
        let savedCard = await task.value
        saveTask = nil
        return savedCard
    }

    func recookStyle(_ style: Style) {
        guard case .ready(let cook) = phase,
              recookingStyle == nil,
              hasCreditsForCook,
              cook.results.contains(where: { $0.style == style })
        else {
            return
        }

        recookingStyle = style
        recookNotice = nil
        usageFeedback = nil
        // The server verifies the signed cook and the answer being replaced, then skips triage.
        let previous = cook.results.first(where: { $0.style == style })
        let request = RecookRequest(
            style: style,
            cook: RecookSource(
                thought: cook.thought,
                thoughtOriginal: cook.thoughtOriginal,
                meta: cook.meta,
                model: cook.model,
                signature: cook.signature
            ),
            previous: previous.map {
                RecookPrevious(reframe: $0.reframe, reframeOriginal: $0.reframeOriginal, signature: $0.signature)
            }
        )
        let attempt: ReframeAttempt
        if pendingRecookStyle == style, let pendingRecookAttempt {
            attempt = pendingRecookAttempt
        } else {
            attempt = ReframeAttempt()
            pendingRecookAttempt = attempt
            pendingRecookStyle = style
        }

        refineTask?.cancel()
        generation &+= 1
        let token = generation
        refineTask = Task { @MainActor in
            defer {
                if generation == token, recookingStyle == style {
                    recookingStyle = nil
                    refineTask = nil
                }
            }

            do {
                let response = try await CookBackgroundTask.run {
                    try await ReframeRetry().run(
                        attempt: attempt,
                        onNewAttempt: { self.pendingRecookAttempt = $0 }
                    ) { current in
                        try await self.reframeService.recook(request, attempt: current)
                    }
                }
                guard !Task.isCancelled, generation == token else {
                    return
                }
                pendingRecookAttempt = nil
                pendingRecookStyle = nil

                switch response {
                case .continueTurn(let message, _, _, _, let usage):
                    applyUsage(usage)
                    // That style no longer fits this thought; keep what we have.
                    recookNotice = message
                case .ready(_, _, let incoming, _, _, _, let usage):
                    applyUsage(usage)
                    guard let replacement = incoming.first(where: { $0.style == style }),
                          case .ready(var current) = phase,
                          let index = current.results.firstIndex(where: { $0.style == style })
                    else {
                        return
                    }

                    current.results[index] = replacement
                    phase = .ready(current)
                    cookHaptic += 1
                }
            } catch {
                guard !Task.isCancelled,
                      generation == token,
                      !HomeViewModel.isCancellation(error) else {
                    return
                }
                if !Self.isAmbiguousReframeFailure(error) {
                    pendingRecookAttempt = nil
                    pendingRecookStyle = nil
                }
                recookNotice = composeFailure(for: error).message
            }
        }
    }

    func resetCompose() {
        generation &+= 1
        refineTask?.cancel()
        refineTask = nil
        saveTask?.cancel()
        saveTask = nil
        composeText = ""
        composeNote = nil
        statement = ""
        turns = []
        recookingStyle = nil
        recookNotice = nil
        pendingRefineAttempt = nil
        pendingRecookAttempt = nil
        pendingRecookStyle = nil
        usageFeedback = nil
        composeErrorAllowsRetry = true
        saveError = nil
        isSaving = false
        composeIsPublic = true
        phase = .composing
    }

    /// Sign-out: a cook still on the way answers into nothing.
    func abandonInFlight() {
        generation &+= 1
    }

    /// A new account's balance starts without the last account's "credits used" line.
    func clearUsageFeedback() {
        usageFeedback = nil
    }

    private func startRefine(attempt: ReframeAttempt) {
        refineTask?.cancel()
        generation &+= 1
        let token = generation
        recookingStyle = nil
        recookNotice = nil
        pendingRecookAttempt = nil
        pendingRecookStyle = nil
        usageFeedback = nil
        composeErrorAllowsRetry = true
        phase = .cooking
        let text = statement
        let followUps = answeredFollowUps

        refineTask = Task { @MainActor in
            do {
                let response = try await CookBackgroundTask.run {
                    try await ReframeRetry().run(
                        attempt: attempt,
                        onNewAttempt: { self.pendingRefineAttempt = $0 }
                    ) { current in
                        try await self.reframeService.refine(
                            text: text,
                            followUps: followUps,
                            attempt: current
                        )
                    }
                }
                guard !Task.isCancelled, generation == token else {
                    return
                }
                pendingRefineAttempt = nil

                switch response {
                case .continueTurn(let message, let options, let safety, let crisisResource, let usage):
                    applyUsage(usage)
                    turns.append(
                        RefineTurn(
                            id: UUID(),
                            message: message,
                            options: options,
                            safety: safety,
                            crisisResource: crisisResource
                        )
                    )
                    phase = .awaitingReply
                case .ready(
                    let thought,
                    let thoughtOriginal,
                    let results,
                    let meta,
                    let model,
                    let signature,
                    let usage
                ):
                    applyUsage(usage)
                    phase = .ready(
                        ReadyCook(
                            thought: thought,
                            thoughtOriginal: thoughtOriginal,
                            results: results,
                            meta: meta,
                            signature: signature,
                            model: model
                        )
                    )
                }
                cookHaptic += 1
            } catch {
                guard !Task.isCancelled,
                      generation == token,
                      !HomeViewModel.isCancellation(error) else {
                    return
                }

                if !Self.isAmbiguousReframeFailure(error) {
                    pendingRefineAttempt = nil
                }
                let failure = composeFailure(for: error)
                composeErrorAllowsRetry = failure.allowsRetry
                phase = .error(failure.message)
            }
            if generation == token {
                refineTask = nil
            }
        }
    }

    private func applyUsage(_ usage: ReframeUsage) {
        host?.applyCookUsage(usage)
        if usage.creditsUsed > 0 {
            usageFeedback = "\(usage.creditsUsed) \(usage.creditsUsed == 1 ? "credit" : "credits") used"
        }
    }

    private func composeFailure(for error: Error) -> (message: String, allowsRetry: Bool) {
        guard case APIError.httpStatus(_, let payload?, _) = error else {
            // No answer came back (a lost connection, a timeout, a restarting server). The
            // thought is still on screen and Retry replays the same attempt.
            switch ReframeFailureKind.of(error) {
            case .network:
                return ("That didn't go through. Your thought is still here. Try again.", true)
            default:
                return ("Couldn't write your angles. Your thought is still here. Try again.", true)
            }
        }
        host?.applyUsage(from: payload)
        let reset = payload.resetsAt
            .flatMap(ISO8601Dates.date(from:))
            .map { " until \($0.formatted(date: .abbreviated, time: .omitted))" }
            ?? ""

        switch payload.code {
        case "SUBSCRIPTION_REQUIRED":
            host?.markTasteEnded()
            return ("Membership is required. Open Settings → Subscription.", false)
        case "INSUFFICIENT_CREDITS":
            return ("You’re out of credits\(reset).", false)
        case "TASTE_RECOOK_UNAVAILABLE":
            return ("New answers aren't available during your free taste.", false)
        case "TASTE_LIMIT_REACHED", "TASTE_ALREADY_CONSUMED":
            host?.markTasteEnded()
            return ("Your free taste is finished. Membership keeps it going.", false)
        case "DAILY_OPERATION_LIMIT":
            return ("You've reached today's cooking limit. Try again tomorrow.", true)
        case "OPERATION_RATE_LIMIT":
            return ("You're cooking too quickly. Wait a moment and try again.", true)
        case "PROVIDER_CALL_LIMIT":
            return ("Today's AI call limit is reached. Try again tomorrow.", true)
        case "IDEMPOTENCY_KEY_REQUIRED", "INVALID_IDEMPOTENCY_KEY":
            return ("This request couldn't be started safely. Try again.", true)
        case "IDEMPOTENCY_CONFLICT":
            return ("This request changed before it completed. Send it again.", true)
        case "OPERATION_RUNNING":
            return ("Still writing your angles. Give it a moment, then try again.", true)
        case "REQUEST_ALREADY_COMPLETED":
            // Retry starts a fresh attempt: the earlier one's result is gone.
            return ("Those angles didn't make it back. Try again.", true)
        case "OPERATION_EXPIRED":
            return ("That took too long. Your thought is still here. Try again.", true)
        case "LLM_ERROR":
            return ("Angles couldn't be written just now. Try again in a moment.", true)
        default:
            return ("Couldn't write your angles. Your thought is still here. Try again.", true)
        }
    }

    /// A request may have reached the server when transport failed, a successful body could
    /// not be decoded, or the cook is still being written. Replaying the same key is the only
    /// retry that cannot spend twice, so these keep their attempt for the Retry button.
    private static func isAmbiguousReframeFailure(_ error: Error) -> Bool {
        switch ReframeFailureKind.of(error) {
        case .network, .running:
            return true
        case .provider, .finishedWithoutResult, .other:
            return false
        }
    }
}
