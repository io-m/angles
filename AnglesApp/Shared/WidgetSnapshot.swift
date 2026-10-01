import Foundation

enum AnglesWidgetConstants {
    static let appGroupIdentifier = "group.app.angles.ios"
    static let favoriteWidgetKind = "FavoriteAngleWidget"
    static let favoritesURL = URL(string: "angles://favorites")!
    static let composeURL = URL(string: "angles://compose")!
}

enum AnglesDeepLink: String, Codable, Equatable {
    case favorites
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
        case .favorites:
            return AnglesWidgetConstants.favoritesURL
        case .compose:
            return AnglesWidgetConstants.composeURL
        }
    }
}

struct FavoriteAngleWidgetItem: Codable, Equatable, Identifiable {
    let id: String
    let cardID: String
    let answer: String
    let style: String
    let styleDisplayName: String
    let lifeAreaLabel: String?
    let favoritedAt: Date
}

struct FavoriteAngleWidgetSnapshot: Codable, Equatable {
    static let empty = FavoriteAngleWidgetSnapshot(items: [], updatedAt: .distantPast)

    let items: [FavoriteAngleWidgetItem]
    let updatedAt: Date
}

struct WidgetSnapshotStore {
    private static let snapshotKey = "angles.favoriteAngleWidget.snapshot"

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

    func loadFavoriteAngles() -> FavoriteAngleWidgetSnapshot {
        guard let data = defaults.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(FavoriteAngleWidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func saveFavoriteAngles(_ snapshot: FavoriteAngleWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    func clearFavoriteAngles() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
