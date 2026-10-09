import Foundation

enum AnglesWidgetConstants {
    static let appGroupIdentifier = "group.app.angles.ios"
    static let heartWidgetKind = "HeartAngleWidget"
    static let heartsURL = URL(string: "angles://hearts")!
    static let composeURL = URL(string: "angles://compose")!
}

enum AnglesDeepLink: String, Codable, Equatable {
    case hearts
    case compose

    init?(url: URL) {
        guard url.scheme?.lowercased() == "angles",
              let host = url.host?.lowercased(),
              let link = AnglesDeepLink(rawValue: host)
        else {
            return nil
        }
        self = link
    }

    var url: URL {
        switch self {
        case .hearts:
            return AnglesWidgetConstants.heartsURL
        case .compose:
            return AnglesWidgetConstants.composeURL
        }
    }
}

struct HeartAngleWidgetItem: Codable, Equatable, Identifiable {
    let id: String
    let cardID: String
    let answer: String
    let style: String
    let styleDisplayName: String
    let lifeAreaLabel: String?
    let heartedAt: Date
}

struct HeartAngleWidgetSnapshot: Codable, Equatable {
    static let empty = HeartAngleWidgetSnapshot(items: [], updatedAt: .distantPast)

    let items: [HeartAngleWidgetItem]
    let updatedAt: Date
}

struct WidgetSnapshotStore {
    private static let snapshotKey = "angles.heartAngleWidget.snapshot"

    private let defaults: UserDefaults

    init?(suiteName: String = AnglesWidgetConstants.appGroupIdentifier) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.defaults = defaults
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadHeartAngles() -> HeartAngleWidgetSnapshot {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(HeartAngleWidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func saveHeartAngles(_ snapshot: HeartAngleWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func clearHeartAngles() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
