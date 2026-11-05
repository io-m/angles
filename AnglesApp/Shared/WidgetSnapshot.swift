import Foundation

enum AnglesWidgetConstants {
    static let appGroupIdentifier = "group.app.angles.ios"
    static let savedWidgetKind = "SavedAngleWidget"
    static let savedURL = URL(string: "angles://saved")!
    static let composeURL = URL(string: "angles://compose")!
}

enum AnglesDeepLink: String, Codable, Equatable {
    case saved
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
        case .saved:
            return AnglesWidgetConstants.savedURL
        case .compose:
            return AnglesWidgetConstants.composeURL
        }
    }
}

struct SavedAngleWidgetItem: Codable, Equatable, Identifiable {
    let id: String
    let cardID: String
    let answer: String
    let style: String
    let styleDisplayName: String
    let lifeAreaLabel: String?
    let savedAt: Date
}

struct SavedAngleWidgetSnapshot: Codable, Equatable {
    static let empty = SavedAngleWidgetSnapshot(items: [], updatedAt: .distantPast)

    let items: [SavedAngleWidgetItem]
    let updatedAt: Date
}

struct WidgetSnapshotStore {
    private static let snapshotKey = "angles.savedAngleWidget.snapshot"

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

    func loadSavedAngles() -> SavedAngleWidgetSnapshot {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(SavedAngleWidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func saveSavedAngles(_ snapshot: SavedAngleWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func clearSavedAngles() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
