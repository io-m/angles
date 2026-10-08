import Observation
import StoreKit
import UIKit

/// Count, cooldown, and attempt cap for an automatic App Store review. The system still
/// decides whether a dialog appears.
enum AppRatingPolicy {
    /// Entitled Save/Post count before the first automatic prompt. Tune here.
    static let minimumEntitledSaves = 3
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            return
        }
        defaults.set(record.successfulEntitledSaveCount + 1, forKey: Key.successfulEntitledSaveCount)
        pendingEligibleSave = true
    }

    /// Call only after compose is closed and the save cover is gone.
    func considerPrompt(context: AppRatingPromptContext) {
        considerPrompt(context: context, now: .now, requestReview: Self.requestSystemReview)
    }

    func considerPrompt(
        context: AppRatingPromptContext,
        now: Date,
        requestReview: () -> Bool
    ) {
        guard pendingEligibleSave else {
            return
        }
        pendingEligibleSave = false
        guard context.allowsAutomaticPrompt else {
            return
        }
        let current = record
        guard AppRatingPolicy.shouldRequestReview(record: current, now: now) else {
            return
        }
        guard requestReview() else {
            return
        }
        defaults.set(now, forKey: Key.lastReviewRequestAt)
        defaults.set(current.reviewRequestCount + 1, forKey: Key.reviewRequestCount)
    }

    func noteSettingsWriteReview(now: Date = .now) {
        Self.noteSettingsWriteReview(defaults: defaults, now: now)
    }

    /// Starts the 90-day cooldown without spending an automatic attempt.
    static func noteSettingsWriteReview(defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(now, forKey: Key.lastReviewRequestAt)
        defaults.set(now, forKey: Key.settingsWriteReviewAt)
    }

    /// iOS 17: `AppStore.requestReview(in:)` is iOS 18+.
    private static func requestSystemReview() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return false
        }
        SKStoreReviewController.requestReview(in: scene)
        return true
    }
}
