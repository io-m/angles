import Foundation
import Observation

/// Count, cooldown, and attempt cap for an automatic App Store review. The system still
/// decides whether a dialog appears.
enum AppRatingPolicy {
    /// Entitled Save/Post count before the first automatic prompt. Tune here.
    static let minimumEntitledSaves = 2
    static let cooldown: TimeInterval = 90 * 24 * 60 * 60
    static let maximumAutomaticAttempts = 2

    static func shouldRequestReview(record: AppRatingRecord, now: Date) -> Bool {
        guard record.successfulEntitledSaveCount >= minimumEntitledSaves else {
            return false
        }
        guard record.reviewRequestCount < maximumAutomaticAttempts else {
            return false
        }
        if let lastReviewRequestAt = record.lastReviewRequestAt,
           now.timeIntervalSince(lastReviewRequestAt) < cooldown {
            return false
        }
        return true
    }
}

/// Whether this install is one where Apple will even consider presenting.
enum AppRatingDistribution {
    /// Debug always can. TestFlight and Xcode are Sandbox — calling still no-ops, so we must
    /// not stamp a cooldown. An unknown environment also skips without stamping; the next Post retries.
    static func allowsSystemReviewPrompt(storeEnvironment: String?) -> Bool {
        #if DEBUG
        true
        #else
        guard let storeEnvironment else {
            return false
        }
        return storeEnvironment.caseInsensitiveCompare("production") == .orderedSame
        #endif
    }
}

struct AppRatingRecord: Equatable, Sendable {
    var successfulEntitledSaveCount: Int
    var lastReviewRequestAt: Date?
    var reviewRequestCount: Int
    var settingsWriteReviewAt: Date?

    static let empty = AppRatingRecord(
        successfulEntitledSaveCount: 0,
        lastReviewRequestAt: nil,
        reviewRequestCount: 0,
        settingsWriteReviewAt: nil
    )
}

/// Screen state after a save celebration has left. Any false check skips the prompt.
struct AppRatingPromptContext: Equatable, Sendable {
    var destinationIsHome: Bool
    var homeIsRevealed: Bool
    var composeVisible: Bool
    var saveCoverVisible: Bool
    var onHomeOrProfile: Bool
    var sceneIsActive: Bool

    var allowsAutomaticPrompt: Bool {
        destinationIsHome
            && homeIsRevealed
            && !composeVisible
            && !saveCoverVisible
            && onHomeOrProfile
            && sceneIsActive
    }
}

/// One owner in `AppRoot`. Settings records a write-review open on the same keys and never
/// calls `requestReview`.
@MainActor
@Observable
final class AppStoreReviewCoordinator {
    private enum Key {
        static let successfulEntitledSaveCount = "angles.rating.successfulEntitledSaveCount"
        static let lastReviewRequestAt = "angles.rating.lastReviewRequestAt"
        static let reviewRequestCount = "angles.rating.reviewRequestCount"
        static let settingsWriteReviewAt = "angles.rating.settingsWriteReviewAt"
    }

    private let defaults: UserDefaults
    /// Set when a non-taste entitled, safety-clear save succeeds. Cleared once the celebration
    /// settles, including when the screen is not a safe moment to ask. No launch catch-up.
    private var pendingEligibleSave = false
    /// AppRoot observes this and asks from the live view. Closures captured at launch must
    /// not call `requestReview` themselves — that copy has a dead environment and stale screen flags.
    private(set) var promptGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resetDebugRatingStateIfNeeded()
    }

    var record: AppRatingRecord {
        AppRatingRecord(
            successfulEntitledSaveCount: defaults.integer(forKey: Key.successfulEntitledSaveCount),
            lastReviewRequestAt: defaults.object(forKey: Key.lastReviewRequestAt) as? Date,
            reviewRequestCount: defaults.integer(forKey: Key.reviewRequestCount),
            settingsWriteReviewAt: defaults.object(forKey: Key.settingsWriteReviewAt) as? Date
        )
    }

    /// Taste never calls this. A crisis session or a locked account does not count.
    func noteSuccessfulEntitledSave(isEntitled: Bool, safetyClear: Bool) {
        pendingEligibleSave = false
        guard isEntitled, safetyClear else {
            log(
                "skip count entitled=\(isEntitled) safetyClear=\(safetyClear) "
                    + snapshot(record)
            )
            return
        }
        defaults.set(record.successfulEntitledSaveCount + 1, forKey: Key.successfulEntitledSaveCount)
        pendingEligibleSave = true
        log("counted save \(snapshot(record))")
    }

    /// Bump so AppRoot's `.task(id:)` runs `considerPrompt` with live scene state.
    func schedulePrompt() {
        promptGeneration += 1
        log("schedule generation=\(promptGeneration) pending=\(pendingEligibleSave) \(snapshot(record))")
    }

    /// Call only after compose is closed and the save cover is gone.
    func considerPrompt(
        context: AppRatingPromptContext,
        storeEnvironment: String?,
        requestReview: () -> Bool
    ) {
        considerPrompt(
            context: context,
            now: .now,
            canPresentSystemReview: AppRatingDistribution.allowsSystemReviewPrompt(
                storeEnvironment: storeEnvironment
            ),
            requestReview: requestReview
        )
    }

    func considerPrompt(
        context: AppRatingPromptContext,
        now: Date,
        canPresentSystemReview: Bool = true,
        requestReview: () -> Bool
    ) {
        guard pendingEligibleSave else {
            log("skip no pending \(snapshot(record))")
            return
        }
        pendingEligibleSave = false
        guard context.allowsAutomaticPrompt else {
            log(
                "skip context destHome=\(context.destinationIsHome) revealed=\(context.homeIsRevealed) "
                    + "compose=\(context.composeVisible) cover=\(context.saveCoverVisible) "
                    + "list=\(context.onHomeOrProfile) active=\(context.sceneIsActive) "
                    + snapshot(record)
            )
            return
        }
        let current = record
        guard AppRatingPolicy.shouldRequestReview(record: current, now: now) else {
            log("skip policy \(snapshot(current))")
            return
        }
        guard canPresentSystemReview else {
            log("skip distribution (TestFlight does not present) \(snapshot(current))")
            return
        }
        guard requestReview() else {
            log("skip request returned false \(snapshot(current))")
            return
        }
        defaults.set(now, forKey: Key.lastReviewRequestAt)
        defaults.set(current.reviewRequestCount + 1, forKey: Key.reviewRequestCount)
        log("asked \(snapshot(record))")
    }

    func noteSettingsWriteReview(now: Date = .now) {
        Self.noteSettingsWriteReview(defaults: defaults, now: now)
    }

    /// Starts the 90-day cooldown without spending an automatic attempt.
    static func noteSettingsWriteReview(defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(now, forKey: Key.lastReviewRequestAt)
        defaults.set(now, forKey: Key.settingsWriteReviewAt)
    }

    /// Debug starts from zero every launch so the two-Post rule can be verified. Release
    /// keeps the lifetime count. Earlier Debug builds left a count of 3+ and only cleared
    /// the cooldown, so the next Post looked like the first and still asked.
    private func resetDebugRatingStateIfNeeded() {
        #if DEBUG
        defaults.removeObject(forKey: Key.successfulEntitledSaveCount)
        defaults.removeObject(forKey: Key.lastReviewRequestAt)
        defaults.removeObject(forKey: Key.reviewRequestCount)
        defaults.removeObject(forKey: Key.settingsWriteReviewAt)
        defaults.removeObject(forKey: "angles.rating.debugHeartCount")
        log("debug reset rating state \(snapshot(record))")
        #endif
    }

    private func snapshot(_ current: AppRatingRecord) -> String {
        let last = current.lastReviewRequestAt.map { ISO8601Dates.string(from: $0) } ?? "nil"
        return "saves=\(current.successfulEntitledSaveCount) "
            + "attempts=\(current.reviewRequestCount) last=\(last)"
    }

    private func log(_ message: String) {
        #if DEBUG
        print("REVIEW \(message)")
        #endif
    }
}
