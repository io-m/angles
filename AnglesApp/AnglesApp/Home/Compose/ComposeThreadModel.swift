import Foundation

/// Which live user bubble is currently being edited in the composer.
enum ComposeEditTarget: Equatable {
    case statement
    case reply(UUID)
}

/// An exchange the AI had already answered, replaced by an edit and kept as a collapsed
/// reference block. `cook` is nil when the AI had only asked a question.
struct ComposeGeneration: Identifiable, Equatable {
    let id: UUID
    var statement: String
    /// Every turn, including a question that was still open.
    var turns: [RefineTurn]
    var cook: ReadyCook?
    var isPublic: Bool
    var recookNotice: String? = nil
    var usageFeedback: String? = nil
    var isExpanded: Bool = false
    var posted: Bool = false
    var saveError: String? = nil

    var threadID: String {
        "archive-\(id.uuidString)"
    }
}

/// What a row of the compose thread shows.
enum ComposeThreadRowKind: Equatable {
    /// Carries its text, so a row on its way out never shows the edited thought.
    case statement(String)
    case question(RefineTurn)
    case reply(RefineTurn)
    case cooking
    case angles(ReadyCook)
    case error(String)

    var debugName: String {
        switch self {
        case .statement: "statement"
        case .question: "question"
        case .reply: "reply"
        case .cooking: "cooking"
        case .angles: "angles"
        case .error: "error"
        }
    }
}

/// One row of the thread. A row keeps its id for as long as it exists (the open question keeps
/// it when it is answered), so only a row that is really new animates. Ids belong to one
/// generation: after an edit every live row is a new view, never the old bubble or card reused.
struct ComposeThreadRow: Identifiable, Equatable {
    let id: String
    let kind: ComposeThreadRowKind
    /// False for a restored prefix after an archive: fade in rather than sliding in again.
    var arrives: Bool = true

    static func id(_ local: String, in generation: UUID) -> String {
        "\(generation.uuidString)/\(local)"
    }

    static func questionID(_ turn: UUID, in generation: UUID) -> String {
        id("q-\(turn)", in: generation)
    }

    static func answerID(_ turn: UUID, in generation: UUID) -> String {
        id("a-\(turn)", in: generation)
    }

    /// Every row of the thread, top to bottom.
    static func rows(
        statement: String,
        turns: [RefineTurn],
        phase: RefinePhase,
        generation: UUID,
        fadeOnlyIDs: Set<String> = []
    ) -> [ComposeThreadRow] {
        guard !statement.isEmpty else {
            return []
        }

        func row(_ id: String, _ kind: ComposeThreadRowKind) -> ComposeThreadRow {
            ComposeThreadRow(id: id, kind: kind, arrives: !fadeOnlyIDs.contains(id))
        }

        var rows = [row(id("statement", in: generation), .statement(statement))]
        for turn in turns where turn.isAnswered {
            rows.append(row(questionID(turn.id, in: generation), .question(turn)))
            rows.append(row(answerID(turn.id, in: generation), .reply(turn)))
        }
        switch phase {
        case .composing:
            break
        case .awaitingReply:
            if let turn = turns.last(where: { !$0.isAnswered }) {
                rows.append(row(questionID(turn.id, in: generation), .question(turn)))
            }
        case .cooking:
            rows.append(row(id("cooking", in: generation), .cooking))
        case .ready(let cook):
            rows.append(row(id("angles", in: generation), .angles(cook)))
        case .error(let message):
            rows.append(row(id("error", in: generation), .error(message)))
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

    init(phase: RefinePhase, isEditing: Bool = false) {
        if isEditing || phase.showsComposer {
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
        isArmed = new.contains(where: { !$0.hasPrefix("archive-") && !known.contains($0) })
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
    case discardIncludingVersions

    /// `nil` closes at once.
    static func resolve(
        isSaving: Bool,
        isBusy: Bool,
        hasWork: Bool,
        hasArchives: Bool = false
    ) -> ComposeLeavePrompt? {
        if isSaving {
            return .busySaving
        }
        if isBusy {
            return .busyWriting
        }
        guard hasWork else {
            return nil
        }
        return hasArchives ? .discardIncludingVersions : .discard
    }

    var title: String {
        switch self {
        case .busyWriting:
            return "This is still writing. Leave anyway?"
        case .busySaving:
            return "Still saving"
        case .discard, .discardIncludingVersions:
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
        case .discardIncludingVersions:
            return "These thoughts, previous versions, and their answers will be gone."
        }
    }

    /// A save that already reached the server lands either way, so there is no honest "leave"
    /// while it runs; it finishes within the 6 s write timeout.
    var allowsLeaving: Bool {
        self != .busySaving
    }

    var isDiscard: Bool {
        self == .discard || self == .discardIncludingVersions
    }

    var confirmTitle: String {
        isDiscard ? "Discard" : "Leave"
    }

    var cancelTitle: String {
        isDiscard ? "Keep" : "Keep going"
    }

    static func restartMessage(isBusy: Bool, hasArchives: Bool = false) -> String {
        if hasArchives {
            if isBusy {
                return "A cook is still running and will be cancelled. This wipes these thoughts, previous versions, and their answers. You can’t undo it."
            }
            return "This wipes these thoughts, previous versions, and their answers. You can’t undo it."
        }
        if isBusy {
            return "A cook is still running and will be cancelled. This wipes these thoughts and their answers. You can’t undo it."
        }
        return "This wipes these thoughts and their answers. You can’t undo it."
    }
}
