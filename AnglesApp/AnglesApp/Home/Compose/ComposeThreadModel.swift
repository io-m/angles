/// What a row of the compose thread shows.
enum ComposeThreadRowKind: Equatable {
    case statement
    case question(RefineTurn)
    case reply(RefineTurn)
    case cooking
    case angles(ReadyCook)
    case error(String)
}

/// One row of the thread. A row keeps its id for as long as it exists (the open question keeps
/// it when it is answered), so only a row that is really new animates.
struct ComposeThreadRow: Identifiable, Equatable {
    let id: String
    let kind: ComposeThreadRowKind

    /// Every row of the thread, top to bottom.
    static func rows(statement: String, turns: [RefineTurn], phase: RefinePhase) -> [ComposeThreadRow] {
        guard !statement.isEmpty else {
            return []
        }
        var rows = [ComposeThreadRow(id: "statement", kind: .statement)]
        for turn in turns where turn.isAnswered {
            rows.append(ComposeThreadRow(id: "q-\(turn.id)", kind: .question(turn)))
            rows.append(ComposeThreadRow(id: "a-\(turn.id)", kind: .reply(turn)))
        }
        switch phase {
        case .composing:
            break
        case .awaitingReply:
            if let turn = turns.last(where: { !$0.isAnswered }) {
                rows.append(ComposeThreadRow(id: "q-\(turn.id)", kind: .question(turn)))
            }
        case .cooking:
            rows.append(ComposeThreadRow(id: "cooking", kind: .cooking))
        case .ready(let cook):
            rows.append(ComposeThreadRow(id: "angles", kind: .angles(cook)))
        case .error(let message):
            rows.append(ComposeThreadRow(id: "error", kind: .error(message)))
        }
        return rows
    }
}

extension RefinePhase {
    /// The composer is there until angles are on screen. A finished cook is one card; the only
    /// way on is Start new.
    var showsComposer: Bool {
        switch self {
        case .composing, .awaitingReply, .error:
            return true
        case .ready, .cooking:
            return false
        }
    }

    var hasPublishableCook: Bool {
        if case .ready(let cook) = self {
            return !cook.results.isEmpty
        }
        return false
    }
}

/// What the bottom bar holds: the input until angles are on screen, then Post (the taste's
/// Save bar is the same bar). While the angles are written the bar's place is held empty.
enum ComposeBottomMode: Equatable {
    case composer
    case post
    case held

    init(phase: RefinePhase) {
        if phase.showsComposer {
            self = .composer
        } else if phase.hasPublishableCook {
            self = .post
        } else {
            self = .held
        }
    }
}

/// Keeps the end of the thread in view while a row arrives. Top-down: while the thread fits,
/// nothing scrolls. A row with a new id scrolls to the end and arms the follow; while armed, every
/// change in the thread's height (the new row settling, the keyboard leaving) scrolls to the end
/// again. It disarms when that row's arrival animation has finished, when the user takes the
/// scroll view, or when the rows change without a new one.
struct ThreadFollow: Equatable {
    private(set) var isArmed = false

    /// True when the end should be scrolled into view.
    mutating func rowsChanged(from old: [String], to new: [String]) -> Bool {
        let known = Set(old)
        isArmed = new.contains(where: { !known.contains($0) })
        return isArmed
    }

    /// True when the end should be scrolled into view.
    func contentHeightChanged() -> Bool {
        isArmed
    }

    mutating func arrivalSettled() {
        isArmed = false
    }

    mutating func userScrolled() {
        isArmed = false
    }
}

/// Why closing compose needs a confirmation, and what it says.
enum ComposeLeavePrompt: Equatable {
    case busyWriting
    case busySaving
    case discard

    /// `nil` closes at once.
    static func resolve(isSaving: Bool, isBusy: Bool, hasWork: Bool) -> ComposeLeavePrompt? {
        if isSaving {
            return .busySaving
        }
        if isBusy {
            return .busyWriting
        }
        return hasWork ? .discard : nil
    }

    var title: String {
        switch self {
        case .busyWriting:
            return "This is still writing. Leave anyway?"
        case .busySaving:
            return "Still saving"
        case .discard:
            return "Discard this thought?"
        }
    }

    var message: String {
        switch self {
        case .busyWriting:
            return "The answers are not ready yet. Leaving cancels this cook."
        case .busySaving:
            return "This takes a few seconds. You can close once the card is saved."
        case .discard:
            return "These thoughts and their answers will be gone."
        }
    }

    /// A save that already reached the server lands either way, so there is no honest "leave"
    /// while it runs; it finishes within the 6 s write timeout.
    var allowsLeaving: Bool {
        self != .busySaving
    }

    var confirmTitle: String {
        self == .discard ? "Discard" : "Leave"
    }

    var cancelTitle: String {
        self == .discard ? "Keep" : "Keep going"
    }

    static func restartMessage(isBusy: Bool) -> String {
        if isBusy {
            return "A cook is still running and will be cancelled. This wipes these thoughts and their answers. You can’t undo it."
        }
        return "This wipes these thoughts and their answers. You can’t undo it."
    }
}
