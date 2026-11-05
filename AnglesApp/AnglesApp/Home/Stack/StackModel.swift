import Foundation
import Observation

/// Every save, pass, rewind, and unsave goes through this one queue, in tap order. A cancelled
/// request can still commit on the server, so a later write always waits for the one before it.
@MainActor
final class DecisionWriter {
    enum Outcome {
        /// The server has the row (or, after a clear, has none).
        case done
        /// The card is gone: deleted, made private, or its author blocked.
        case gone
        case failed(Error)
    }

    private static let retryDelays: [Duration] = [.milliseconds(600), .seconds(2), .seconds(5)]

    private let cardsService: CardsService
    private var tail: Task<Void, Never>?
    private var generation = 0
    private var pending: [UUID: Int] = [:]

    init(cardsService: CardsService) {
        self.cardsService = cardsService
    }

    /// A write for this card is queued or on the wire, so a list the server sends now may not
    /// have it yet.
    func isPending(_ id: UUID) -> Bool {
        pending[id, default: 0] > 0
    }

    func enqueue(_ id: UUID, _ write: DecisionWrite, completion: @escaping @MainActor (Outcome) -> Void) {
        let previous = tail
        let generation = generation
        pending[id, default: 0] += 1
        tail = Task { @MainActor in
            await previous?.value
            guard generation == self.generation else {
                return
            }
            let outcome = await self.perform(id, write)
            guard generation == self.generation else {
                return
            }
            self.settled(id)
            completion(outcome)
        }
    }

    /// Sign-out: nothing queued for the last account is sent.
    func reset() {
        generation &+= 1
        tail?.cancel()
        tail = nil
        pending = [:]
    }

    private func settled(_ id: UUID) {
        let left = pending[id, default: 1] - 1
        pending[id] = left > 0 ? left : nil
    }

    private func perform(_ id: UUID, _ write: DecisionWrite) async -> Outcome {
        let key = id.uuidString.lowercased()
        var attempt = 0
        while true {
            do {
                switch write {
                case .put(let body):
                    _ = try await cardsService.decide(id: key, body)
                case .clear:
                    try await cardsService.clearDecision(id: key)
                }
                return .done
            } catch {
                if case APIError.httpStatus(404, _, _) = error {
                    return .gone
                }
                guard Self.isRetryable(error), attempt < Self.retryDelays.count, !Task.isCancelled else {
                    return .failed(error)
                }
                try? await Task.sleep(for: Self.retryDelays[attempt])
                attempt += 1
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if HomeViewModel.isCancellation(error) {
            return false
        }
        if case APIError.httpStatus(let status, _, _) = error {
            return status == 408 || status == 429 || status >= 500
        }
        return true
    }
}

@MainActor
protocol StackHost: AnyObject {
    /// A save on the stack. The card carries its new `decision`.
    func stackSaved(_ card: HomeCard)
    /// A save was taken back by a rewind or a failed write. The card carries the decision it
    /// had before.
    func stackUnsaved(_ card: HomeCard)
    func stackCardGone(_ id: UUID)
    func stackWriteFailed(_ error: Error, _ message: String)
    func isBlocked(_ card: HomeCard) -> Bool
}

/// Life areas and moods that narrow the stack. Empty sets mean everything.
struct StackFilter: Equatable, Sendable {
    var categories: Set<ThoughtCategory> = []
    var emotions: Set<Emotion> = []

    var appliedCount: Int {
        categories.count + emotions.count
    }

    var isEmpty: Bool {
        appliedCount == 0
    }
}

enum StackLoadState: Equatable {
    case idle
    case loading
    case failed
}

/// Home: one visit's stack, its paging, and its decisions. The deck itself is `StackDeck`.
@MainActor
@Observable
final class StackModel {
    static let pageSize = 12
    /// Back after this long away starts a new visit.
    static let staleAfter: TimeInterval = 30 * 60

    private(set) var deck = StackDeck()
    private(set) var loadState: StackLoadState = .idle
    /// The first page of the first visit has answered, with cards or an error. Launch waits on it.
    private(set) var firstLoadFinished = false
    /// Bumped by every visit so the view drops anything it was animating.
    private(set) var visitToken = 0
    /// Sent with every page; changing it starts a new visit.
    private(set) var filter = StackFilter()

    @ObservationIgnored weak var host: StackHost?
    @ObservationIgnored private let cardsService: CardsService
    @ObservationIgnored private let writer: DecisionWriter
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var visitGeneration = 0
    @ObservationIgnored private var backgroundedAt: Date?

    init(cardsService: CardsService, writer: DecisionWriter) {
        self.cardsService = cardsService
        self.writer = writer
    }

    // MARK: - Visits

    /// Cold launch. A visit already under way is kept.
    func startVisitIfNeeded() {
        guard !deck.hasLoadedOnce, fetchTask == nil else {
            return
        }
        fetch()
    }

    /// Check again, or back after `staleAfter`: a new session, new jitter, and inputs frozen now.
    func startNewVisit() {
        visitGeneration &+= 1
        visitToken &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        deck = StackDeck()
        loadState = .idle
        fetch()
    }

    func apply(_ next: StackFilter) {
        guard next != filter else {
            return
        }
        filter = next
        startNewVisit()
    }

    func noteBackground(at date: Date = Date()) {
        backgroundedAt = date
    }

    func noteForeground(at date: Date = Date()) {
        defer { backgroundedAt = nil }
        guard let backgroundedAt, deck.hasLoadedOnce,
              date.timeIntervalSince(backgroundedAt) >= Self.staleAfter
        else {
            return
        }
        startNewVisit()
    }

    func retry() {
        guard fetchTask == nil else {
            return
        }
        fetch()
    }

    func reset() {
        visitGeneration &+= 1
        visitToken &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        deck = StackDeck()
        loadState = .idle
        firstLoadFinished = false
        backgroundedAt = nil
        filter = StackFilter()
    }

    private func fetchMoreIfNeeded() {
        guard deck.wantsMore, fetchTask == nil else {
            return
        }
        // An empty deck after a failure waits for Try again rather than looping.
        if loadState == .failed, deck.cards.isEmpty {
            return
        }
        fetch()
    }

    private func fetch() {
        let generation = visitGeneration
        let session = deck.session
        let seen = deck.seen
        let filter = filter
        loadState = .loading
        fetchTask = Task { @MainActor in
            do {
                let response = try await cardsService.stack(
                    limit: Self.pageSize,
                    session: session,
                    seen: seen,
                    filter: filter
                )
                guard generation == visitGeneration, !Task.isCancelled else {
                    return
                }
                let cards = response.cards
                    .compactMap(HomeCard.init(stored:))
                    .filter { !(host?.isBlocked($0) ?? false) }
                deck.receive(
                    cards,
                    receivedIds: response.receivedIds,
                    session: response.session,
                    exhausted: response.exhausted
                )
                loadState = .idle
                firstLoadFinished = true
                fetchTask = nil
                // A page this build could not show still moved the server along.
                if !response.receivedIds.isEmpty {
                    fetchMoreIfNeeded()
                }
            } catch {
                guard generation == visitGeneration, !Task.isCancelled else {
                    return
                }
                fetchTask = nil
                guard !HomeViewModel.isCancellation(error) else {
                    loadState = .idle
                    return
                }
                loadState = .failed
                firstLoadFinished = true
            }
        }
    }

    // MARK: - Decisions

    func show(_ style: Style, on id: UUID) {
        deck.show(style, on: id)
    }

    /// Takes the top card off right away; the write follows on the queue.
    @discardableResult
    func decide(_ kind: DecisionKind) -> StackStep? {
        guard let step = deck.decide(kind) else {
            return nil
        }
        if kind == .save {
            var saved = step.card
            saved.decision = CardDecision(step.request)
            host?.stackSaved(saved)
        }
        let generation = visitGeneration
        writer.enqueue(step.card.id, .put(step.request)) { [weak self] outcome in
            self?.settle(step, outcome: outcome, generation: generation, isUndo: false)
        }
        fetchMoreIfNeeded()
        return step
    }

    /// The last decision of this visit, undone: the card is back on top and its row is what it was.
    @discardableResult
    func rewind() -> StackStep? {
        guard let undone = deck.rewind() else {
            return nil
        }
        let step = undone.step
        if step.kind == .save {
            host?.stackUnsaved(step.card)
        }
        let generation = visitGeneration
        writer.enqueue(step.card.id, undone.write) { [weak self] outcome in
            self?.settle(step, outcome: outcome, generation: generation, isUndo: true)
        }
        return step
    }

    /// A blocked author or a reported card leaves the stack and rewind.
    func remove(where shouldRemove: (HomeCard) -> Bool) {
        deck.remove(where: shouldRemove)
        fetchMoreIfNeeded()
    }

    func updateCards(_ body: (inout HomeCard) -> Void) {
        deck.updateCards(body)
    }

    private func settle(_ step: StackStep, outcome: DecisionWriter.Outcome, generation: Int, isUndo: Bool) {
        let id = step.card.id
        switch outcome {
        case .done:
            if generation == visitGeneration, !isUndo {
                deck.confirm(id)
            }
        case .gone:
            if generation == visitGeneration {
                deck.remove { $0.id == id }
            }
            host?.stackCardGone(id)
        case .failed(let error):
            if step.kind == .save, !isUndo {
                host?.stackUnsaved(step.card)
            }
            host?.stackWriteFailed(
                error,
                isUndo
                    ? "Couldn't undo that. Check your connection."
                    : step.kind == .save
                        ? "Couldn't love that card. Check your connection."
                        : "Couldn't pass on that card. Check your connection."
            )
        }
    }
}
