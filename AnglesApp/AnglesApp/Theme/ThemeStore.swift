import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    private enum Keys {
        static let appearance = "angles.appearanceMode"
        static let hue = "angles.accentHue"
        static let saturation = "angles.accentSaturation"
        static let brightness = "angles.accentBrightness"
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance)
        }
    }

    @Published var accentHSB: AccentHSB {
        didSet {
            UserDefaults.standard.set(accentHSB.hue, forKey: Keys.hue)
            UserDefaults.standard.set(accentHSB.saturation, forKey: Keys.saturation)
            UserDefaults.standard.set(accentHSB.brightness, forKey: Keys.brightness)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.appearance),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }

        if defaults.object(forKey: Keys.hue) != nil {
            accentHSB = AccentHSB(
                hue: defaults.double(forKey: Keys.hue),
                saturation: defaults.double(forKey: Keys.saturation),
                brightness: defaults.double(forKey: Keys.brightness)
            )
        } else {
            accentHSB = .default
        }
    }
}
