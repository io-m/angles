import Foundation

/// One decision made on the stack this visit, kept so rewind can put the card and its
/// server row back exactly as they were.
struct StackStep: Equatable {
    /// The card as it was before the decision, including the row it had (`decision`).
    let card: HomeCard
    let request: DecisionRequest
    /// The angle on screen and the angles seen when it was decided.
    let shownStyle: Style
    let checked: [Style]

    var kind: DecisionKind { request.kind }
}

/// The write that undoes a step: the row the card had before, or no row at all.
enum DecisionWrite: Equatable {
    case put(DecisionRequest)
    case clear
}

/// The stack for one visit, without views or networking. The top card is `cards[0]`.
struct StackDeck: Equatable {
    /// Ask for the next page once this few cards are left.
    static let prefetchThreshold = 5
    /// The server reads at most this many `seen` ids.
    static let maxSeen = 200

    private(set) var cards: [HomeCard] = []
    private(set) var session: String?
    private(set) var exhausted = false
    private(set) var history: [StackStep] = []
    /// Every id the server handed out this visit, in order, lowercased. Includes cards this
    /// build could not decode, so the server does not send them again.
    private(set) var handedOut: [String] = []
    /// Cards whose decision the server has confirmed. The server leaves them out on its own.
    private(set) var confirmed: Set<String> = []
    private var shown: [UUID: Style] = [:]
    private var checkedStyles: [UUID: [Style]] = [:]

    var top: HomeCard? { cards.first }
    var behind: HomeCard? { cards.dropFirst().first }
    var canRewind: Bool { !history.isEmpty }
    var hasLoadedOnce: Bool { session != nil }
    /// Nothing left on the phone or the server: the end card.
    var isFinished: Bool { cards.isEmpty && exhausted }
    var wantsMore: Bool { !exhausted && cards.count <= Self.prefetchThreshold }

    /// Ids already handed out this visit that the server cannot yet leave out by itself.
    var seen: [String] {
        Array(handedOut.filter { !confirmed.contains($0) }.suffix(Self.maxSeen))
    }

    func style(for card: HomeCard) -> Style {
        shown[card.id] ?? card.openingStyle
    }

    /// Angles that have been on screen, in the order they were seen. The opening one counts.
    func checked(for card: HomeCard) -> [Style] {
        checkedStyles[card.id] ?? [card.openingStyle]
    }

    mutating func receive(_ incoming: [HomeCard], receivedIds: [String], session: String, exhausted: Bool) {
        self.session = session
        self.exhausted = exhausted
        var known = Set(handedOut)
        for id in receivedIds.map({ $0.lowercased() }) where known.insert(id).inserted {
            handedOut.append(id)
        }
        let onDeck = Set(cards.map(\.id))
        for card in incoming where !card.isOwner && !onDeck.contains(card.id) {
            guard !history.contains(where: { $0.card.id == card.id }) else {
                continue
            }
            let key = Self.key(card.id)
            if known.insert(key).inserted {
                handedOut.append(key)
            }
            cards.append(card)
            shown[card.id] = card.openingStyle
            checkedStyles[card.id] = [card.openingStyle]
        }
    }

    /// The angle bar or a tap moved the card to `style`. It now counts as seen.
    mutating func show(_ style: Style, on id: UUID) {
        guard let card = cards.first(where: { $0.id == id }), card.hasStyle(style) else {
            return
        }
        shown[id] = style
        var seen = checkedStyles[id] ?? [card.openingStyle]
        if !seen.contains(style) {
            seen.append(style)
        }
        checkedStyles[id] = seen
    }

    /// Takes the top card off the deck and returns the row to write for it.
    mutating func decide(_ kind: DecisionKind) -> StackStep? {
        guard let card = cards.first else {
            return nil
        }
        let style = style(for: card)
        let checked = checked(for: card)
        let step = StackStep(
            card: card,
            request: Self.request(kind: kind, card: card, style: style, checked: checked),
            shownStyle: style,
            checked: checked
        )
        cards.removeFirst()
        history.append(step)
        confirmed.remove(Self.key(card.id))
        return step
    }

    /// Puts the last decided card back on top, on the angle it was showing.
    mutating func rewind() -> (step: StackStep, write: DecisionWrite)? {
        guard let step = history.popLast() else {
            return nil
        }
        let id = step.card.id
        cards.removeAll { $0.id == id }
        cards.insert(step.card, at: 0)
        shown[id] = step.shownStyle
        checkedStyles[id] = step.checked
        confirmed.remove(Self.key(id))
        return (step, Self.undo(step))
    }

    /// The server has this card's decision, so it no longer needs to be named in `seen`.
    mutating func confirm(_ id: UUID) {
        let key = Self.key(id)
        guard handedOut.contains(key), !cards.contains(where: { $0.id == id }) else {
            return
        }
        confirmed.insert(key)
    }

    /// A blocked author, a report, or a card that is gone: off the deck and out of rewind.
    mutating func remove(where shouldRemove: (HomeCard) -> Bool) {
        cards.removeAll(where: shouldRemove)
        history.removeAll { shouldRemove($0.card) }
    }

    mutating func updateCards(_ body: (inout HomeCard) -> Void) {
        for index in cards.indices {
            body(&cards[index])
        }
    }

    /// The full row for a decision. Angles seen on an earlier pass stay seen, and a pass
    /// counts up to `maxDecisionPasses`.
    static func request(kind: DecisionKind, card: HomeCard, style: Style, checked: [Style]) -> DecisionRequest {
        let prior = card.decision
        var union: [Style] = []
        for candidate in (prior?.checkedStyles ?? []) + checked + [style]
        where card.hasStyle(candidate) && !union.contains(candidate) {
            union.append(candidate)
        }
        let priorPasses = prior?.passes ?? 0
        let passes = kind == .pass ? min(maxDecisionPasses, priorPasses + 1) : priorPasses
        return DecisionRequest(kind: kind, style: style, checkedStyles: union, passes: passes)
    }

    /// Unsave from a list: every angle counts as seen, so the card never comes back.
    static func unsaveRequest(for card: HomeCard) -> DecisionRequest {
        DecisionRequest(
            kind: .pass,
            style: card.decision?.style ?? card.openingStyle,
            checkedStyles: card.styles,
            passes: maxDecisionPasses
        )
    }

    static func undo(_ step: StackStep) -> DecisionWrite {
        guard let prior = step.card.decision else {
            return .clear
        }
        return .put(
            DecisionRequest(
                kind: prior.kind,
                style: prior.style,
                checkedStyles: prior.checkedStyles,
                passes: prior.passes
            )
        )
    }

    private static func key(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

extension CardDecision {
    /// The row a write will leave behind, for the phone's copy until the server answers.
    init(_ request: DecisionRequest, at date: Date = Date()) {
        self.init(
            kind: request.kind,
            style: request.style,
            checkedStyles: request.checkedStyles,
            passes: request.passes,
            decidedAt: ISO8601Dates.string(from: date)
        )
    }
}
