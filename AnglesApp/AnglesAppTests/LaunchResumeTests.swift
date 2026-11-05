import Foundation
import Testing
@testable import Angles

struct SessionSnapshotStoreTests {
    @Test func roundTripsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SessionSnapshotStore(directory: directory)
        #expect(store.load() == nil)

        let body = SessionBody(
            id: "00000000-0000-4000-8000-000000000001",
            initials: "JM",
            name: "Josip",
            tasteCompletedAt: "2026-10-01T12:00:00.000Z",
            tasteConsumedAt: nil,
            termsAcceptedAt: "2026-10-01T12:00:00.000Z",
            avatarUrl: nil,
            notifyFollows: true
        )
        store.save(body)
        #expect(store.load() == body)

        store.delete()
        #expect(store.load() == nil)
    }
}
