import Foundation

enum RefineMock {
    static let readyWordThreshold = 24

    static let clarifyBank: [(question: String, options: [String])] = [
        (
            "What stings most about this?",
            ["The outcome", "How I look to others", "That I can't control it"]
        ),
        (
            "What do you want from here?",
            ["To feel calmer", "A next step", "To be honest with myself"]
        ),
        (
            "Anything the first take would miss?",
            ["It's been going on a while", "I already know what I should do", "I'm mostly tired"]
        ),
    ]

    static let variants: [Style: [String]] = [
        .stoic: [
            "You cannot control the outcome, only how you meet the moment.",
            "The course list is not yours to command. What you do next is.",
            "Wanting a path is clear. Waiting for a perfect option is optional.",
        ],
        .optimistic: [
            "This is one hard moment, not the shape of everything ahead.",
            "The path is narrower than you hoped, not closed.",
            "You already know the trade. That is a start, not a stop.",
        ],
        .humorous: [
            "Your brain has submitted a dramatic first draft. Edits are allowed.",
            "Plot twist: the catalog forgot to stock the one option you wanted.",
            "A missing course is not a missing career. It is a missing SKU.",
        ],
        .toughLove: [
            "Stop waiting for certainty. Take the smallest useful step now.",
            "A missing option is a constraint, not an identity. Move anyway.",
            "Stop auditioning obstacles. Pick the next trainer, town, or book and start.",
        ],
    ]

    static var cannedReframes: [Style: String] {
        var first: [Style: String] = [:]
        for (style, list) in variants {
            first[style] = list.first
        }
        return first
    }

    enum Outcome: Equatable {
        case clarify(question: String, options: [String])
        case ready
    }

    static func decide(text: String, answeredFollowUps: Int) -> Outcome {
        if answeredFollowUps >= 3 {
            return .ready
        }

        if answeredFollowUps == 0 && wordCount(text) >= readyWordThreshold {
            return .ready
        }

        if answeredFollowUps >= 1 {
            return .ready
        }

        let index = min(answeredFollowUps, clarifyBank.count - 1)
        let entry = clarifyBank[index]
        return .clarify(question: entry.question, options: entry.options)
    }

    static func results() -> [ReframeResult] {
        Style.allCases.map { style in
            ReframeResult(style: style, reframe: cannedReframes[style] ?? "")
        }
    }

    static func nextVariant(style: Style, after current: String) -> String {
        let list = variants[style] ?? [current]
        guard !list.isEmpty else {
            return current
        }

        if let index = list.firstIndex(of: current) {
            return list[(index + 1) % list.count]
        }

        return list[0]
    }

    static func wordCount(_ text: String) -> Int {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
    }
}
