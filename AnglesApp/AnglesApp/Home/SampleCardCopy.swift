import Foundation

/// Seed copy for the in-memory library until History persists real cards.
/// Nothing here decides anything: the API owns clarify vs ready.
enum SampleCardCopy {
    static let reframes: [Style: String] = [
        .stoic: "You cannot control the outcome, only how you meet the moment.",
        .optimistic: "This is one hard moment, not the shape of everything ahead.",
        .humorous: "Your brain has submitted a dramatic first draft. Edits are allowed.",
        .toughLove: "Stop waiting for certainty. Take the smallest useful step now.",
    ]
}
