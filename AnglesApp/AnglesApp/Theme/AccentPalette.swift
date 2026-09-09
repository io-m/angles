import SwiftUI

struct AccentHSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    /// Default: H≈9°, S≈76%, B≈94% — orange-red, distinct from charcoal neutrals.
    static let `default` = AccentHSB(hue: 9 / 360, saturation: 0.76, brightness: 0.94)

    static let presets: [AccentHSB] = [
        .default,
        AccentHSB(hue: 22 / 360, saturation: 0.62, brightness: 0.78),
        AccentHSB(hue: 38 / 360, saturation: 0.70, brightness: 0.88),
        AccentHSB(hue: 145 / 360, saturation: 0.38, brightness: 0.58),
        AccentHSB(hue: 186 / 360, saturation: 0.52, brightness: 0.70),
        AccentHSB(hue: 214 / 360, saturation: 0.58, brightness: 0.76),
        AccentHSB(hue: 268 / 360, saturation: 0.42, brightness: 0.70),
        AccentHSB(hue: 348 / 360, saturation: 0.56, brightness: 0.78),
    ]

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    func matches(_ other: AccentHSB) -> Bool {
        let hueDelta = abs(hue - other.hue)
        let hueGap = min(hueDelta, 1 - hueDelta)
        return hueGap < 0.004
            && abs(saturation - other.saturation) < 0.02
            && abs(brightness - other.brightness) < 0.02
    }
}

struct AccentPalette: Equatable {
    var accent: Color
    var accentDeep: Color
    var accentSoft: Color
    var accentWash: Color
    var accentGlow: Color

    static let `default` = AccentPalette(from: .default, colorScheme: .light)

    init(from hsb: AccentHSB, colorScheme: ColorScheme) {
        let dark = colorScheme == .dark
        let hue = hsb.hue
        let sat = hsb.saturation
        let bright = hsb.brightness

        let accentBright = dark ? min(1, bright + 0.04) : bright
        self.accent = Color(hue: hue, saturation: sat, brightness: accentBright)
        self.accentGlow = self.accent.opacity(dark ? 0.30 : 0.35)

        if dark {
            self.accentDeep = Self.clampedDeep(
                hue: hue,
                saturation: min(1, sat + 0.04),
                brightness: min(0.96, accentBright + 0.14),
                isDark: true
            )
            self.accentSoft = Color(
                hue: hue,
                saturation: max(0, sat - 0.30),
                brightness: max(0, accentBright - 0.10)
            )
            self.accentWash = Color(
                hue: hue,
                saturation: max(0, sat - 0.50),
                brightness: max(0, accentBright - 0.34)
            ).opacity(0.45)
        } else {
            self.accentDeep = Self.clampedDeep(
                hue: hue,
                saturation: min(1, sat + 0.06),
                brightness: max(0.30, bright - 0.22),
                isDark: false
            )
            self.accentSoft = Color(
                hue: hue,
                saturation: max(0, sat - 0.35),
                brightness: min(0.90, bright + 0.18)
            )
            self.accentWash = Color(
                hue: hue,
                saturation: max(0, sat - 0.55),
                brightness: min(0.96, bright + 0.30)
            )
        }
    }

    private static func clampedDeep(
        hue: Double,
        saturation: Double,
        brightness: Double,
        isDark: Bool
    ) -> Color {
        var brightness = brightness
        for _ in 0..<40 {
            if Contrast.passes(hue: hue, saturation: saturation, brightness: brightness, isDark: isDark) {
                break
            }
            if isDark {
                let next = min(0.98, brightness + 0.02)
                if next == brightness { break }
                brightness = next
            } else {
                let next = max(0.02, brightness - 0.02)
                if next == brightness { break }
                brightness = next
            }
        }
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

private struct AccentPaletteKey: EnvironmentKey {
    static let defaultValue = AccentPalette.default
}

extension EnvironmentValues {
    var accentPalette: AccentPalette {
        get { self[AccentPaletteKey.self] }
        set { self[AccentPaletteKey.self] = newValue }
    }
}

private enum Contrast {
    static let minimum = 4.5

    static func passes(hue: Double, saturation: Double, brightness: Double, isDark: Bool) -> Bool {
        let rgb = hsbToRGB(h: hue, s: saturation, b: brightness)
        let text = relativeLuminance(rgb)
        let paper = relativeLuminance(isDark ? ColorTokens.paperDarkRGB : ColorTokens.paperLightRGB)
        let grey = relativeLuminance(isDark ? ColorTokens.greyDarkRGB : ColorTokens.greyLightRGB)
        return ratio(text, paper) >= minimum && ratio(text, grey) >= minimum
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double {
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    private static func hsbToRGB(h: Double, s: Double, b: Double) -> (Double, Double, Double) {
        let wrapped = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let sector = wrapped * 6
        let i = Int(sector)
        let f = sector - Double(i)
        let p = b * (1 - s)
        let q = b * (1 - f * s)
        let t = b * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }
}
