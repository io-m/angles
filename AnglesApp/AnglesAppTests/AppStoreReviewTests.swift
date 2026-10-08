import Foundation
import Testing
@testable import Angles

struct AppRatingPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(saves: Int, attempts: Int = 0, lastReview: Date? = nil) -> AppRatingRecord {
        AppRatingRecord(
            successfulEntitledSaveCount: saves,
            lastReviewRequestAt: lastReview,
            reviewRequestCount: attempts,
            settingsWriteReviewAt: nil
        )
    }

    @Test func fewerThanThreeSavesDoesNotQualify() {
        #expect(!AppRatingPolicy.shouldRequestReview(record: record(saves: 0), now: now))
        #expect(!AppRatingPolicy.shouldRequestReview(record: record(saves: 1), now: now))
        #expect(!AppRatingPolicy.shouldRequestReview(record: record(saves: 2), now: now))
    }

    @Test func thirdSaveQualifies() {
        #expect(AppRatingPolicy.shouldRequestReview(record: record(saves: 3), now: now))
    }

    @Test func cooldownBlocksUntilNinetyDays() {
        let asked = record(saves: 3, attempts: 1, lastReview: now)
        let early = now.addingTimeInterval(AppRatingPolicy.cooldown - 1)
        #expect(!AppRatingPolicy.shouldRequestReview(record: asked, now: early))
        let due = now.addingTimeInterval(AppRatingPolicy.cooldown)
        #expect(AppRatingPolicy.shouldRequestReview(record: asked, now: due))
    }

    @Test func twoAttemptsIsTheLifetimeCap() {
        let twice = record(
            saves: 6,
            attempts: AppRatingPolicy.maximumAutomaticAttempts,
            lastReview: now.addingTimeInterval(-AppRatingPolicy.cooldown)
        )
        #expect(!AppRatingPolicy.shouldRequestReview(record: twice, now: now))
    }
}

@MainActor
struct AppStoreReviewCoordinatorTests {
    private let settled = AppRatingPromptContext(
        destinationIsHome: true,
        homeIsRevealed: true,
        composeVisible: false,
        saveCoverVisible: false,
        onHomeOrProfile: true,
        sceneIsActive: true
    )

    @Test func everyGuardCanBlockThePrompt() {
        #expect(settled.allowsAutomaticPrompt)
        #expect(!blocked { $0.destinationIsHome = false })
        #expect(!blocked { $0.homeIsRevealed = false })
        #expect(!blocked { $0.composeVisible = true })
        #expect(!blocked { $0.saveCoverVisible = true })
        #expect(!blocked { $0.onHomeOrProfile = false })
        #expect(!blocked { $0.sceneIsActive = false })
    }

    @Test func firstTwoSavesDoNotRequestAndTheThirdDoes() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var requests = 0
        let now = harness.now
        harness.save(at: now, context: settled, requests: &requests)
        harness.save(at: now, context: settled, requests: &requests)
        #expect(requests == 0)
        #expect(harness.coordinator.record.successfulEntitledSaveCount == 2)

        harness.save(at: now, context: settled, requests: &requests)
        harness.coordinator.considerPrompt(context: settled, now: now) {
            requests += 1
            return true
        }
        #expect(requests == 1)
        #expect(harness.coordinator.record.reviewRequestCount == 1)
        #expect(harness.coordinator.record.lastReviewRequestAt == now)
    }

    @Test func secondPromptWaitsNinetyDaysAndAThirdNeverFires() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var requests = 0
        let first = harness.now
        for _ in 0..<3 {
            harness.save(at: first, context: settled, requests: &requests)
        }
        #expect(requests == 1)

        let duringCooldown = first.addingTimeInterval(AppRatingPolicy.cooldown - 1)
        harness.save(at: duringCooldown, context: settled, requests: &requests)
        #expect(requests == 1)

        let second = first.addingTimeInterval(AppRatingPolicy.cooldown)
        harness.save(at: second, context: settled, requests: &requests)
        #expect(requests == 2)
        #expect(harness.coordinator.record.reviewRequestCount == 2)

        let later = second.addingTimeInterval(AppRatingPolicy.cooldown)
        harness.save(at: later, context: settled, requests: &requests)
        #expect(requests == 2)
        #expect(harness.coordinator.record.reviewRequestCount == 2)
        #expect(harness.coordinator.record.successfulEntitledSaveCount == 6)
    }

    @Test func lockedAndCrisisSavesDoNotCount() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var requests = 0
        harness.coordinator.noteSuccessfulEntitledSave(isEntitled: false, safetyClear: true)
        harness.coordinator.noteSuccessfulEntitledSave(isEntitled: true, safetyClear: false)
        harness.coordinator.considerPrompt(context: settled, now: harness.now) {
            requests += 1
            return true
        }
        #expect(requests == 0)
        #expect(harness.coordinator.record.successfulEntitledSaveCount == 0)
        #expect(harness.coordinator.record.reviewRequestCount == 0)
    }

    @Test func coveredScreenDoesNotSpendAnAttempt() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var requests = 0
        var covered = settled
        covered.composeVisible = true
        for _ in 0..<3 {
            harness.save(at: harness.now, context: covered, requests: &requests)
        }
        #expect(requests == 0)
        #expect(harness.coordinator.record.reviewRequestCount == 0)
        #expect(harness.coordinator.record.lastReviewRequestAt == nil)

        harness.save(at: harness.now, context: settled, requests: &requests)
        #expect(requests == 1)
        #expect(harness.coordinator.record.reviewRequestCount == 1)
    }

    @Test func missingSceneDoesNotRecordAnAttempt() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var attempts = 0
        for _ in 0..<3 {
            harness.coordinator.noteSuccessfulEntitledSave(isEntitled: true, safetyClear: true)
            harness.coordinator.considerPrompt(context: settled, now: harness.now) {
                attempts += 1
                return false
            }
        }
        #expect(attempts == 1)
        #expect(harness.coordinator.record.reviewRequestCount == 0)

        harness.coordinator.considerPrompt(context: settled, now: harness.now) {
            attempts += 1
            return true
        }
        #expect(attempts == 1)

        harness.coordinator.noteSuccessfulEntitledSave(isEntitled: true, safetyClear: true)
        harness.coordinator.considerPrompt(context: settled, now: harness.now) {
            attempts += 1
            return true
        }
        #expect(attempts == 2)
        #expect(harness.coordinator.record.reviewRequestCount == 1)
    }

    @Test func settingsWriteReviewDelaysTheAutomaticPrompt() throws {
        let harness = try ReviewHarness()
        defer { harness.cleanup() }
        var requests = 0
        let opened = harness.now
        harness.coordinator.noteSettingsWriteReview(now: opened)
        #expect(harness.coordinator.record.settingsWriteReviewAt == opened)
        #expect(harness.coordinator.record.reviewRequestCount == 0)

        for _ in 0..<3 {
            harness.save(at: opened.addingTimeInterval(86_400), context: settled, requests: &requests)
        }
        #expect(requests == 0)

        let due = opened.addingTimeInterval(AppRatingPolicy.cooldown)
        harness.save(at: due, context: settled, requests: &requests)
        #expect(requests == 1)
        #expect(harness.coordinator.record.reviewRequestCount == 1)
    }

    private func blocked(_ change: (inout AppRatingPromptContext) -> Void) -> Bool {
        var context = settled
        change(&context)
        return context.allowsAutomaticPrompt
    }
}

@MainActor
private final class ReviewHarness {
    let name: String
    let defaults: UserDefaults
    let coordinator: AppStoreReviewCoordinator
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        name = "angles.rating.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        self.defaults = defaults
        coordinator = AppStoreReviewCoordinator(defaults: defaults)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: name)
    }

    func save(at now: Date, context: AppRatingPromptContext, requests: inout Int) {
        coordinator.noteSuccessfulEntitledSave(isEntitled: true, safetyClear: true)
        coordinator.considerPrompt(context: context, now: now) {
            requests += 1
            return true
        }
    }
}
