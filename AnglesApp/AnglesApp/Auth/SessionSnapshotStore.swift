import Foundation

/// Last confirmed session body for this install. Lets launch resume without waiting
/// on `GET /profile/session`. A 401 still clears it.
struct SessionSnapshotStore: Sendable {
    private let fileURL: URL

    init(directory: URL = SessionSnapshotStore.defaultDirectory()) {
        fileURL = directory.appendingPathComponent("session.json", isDirectory: false)
    }

    func load() -> SessionBody? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionBody.self, from: data)
    }

    func save(_ body: SessionBody) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(body)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Launch still has the Keychain token; a missing body only costs a network restore.
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func defaultDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("angles", isDirectory: true)
    }
}
