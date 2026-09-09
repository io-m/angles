import SwiftUI

struct ColorTokens {
    static let paperLight = Color(red: 0xFD / 255, green: 0xFB / 255, blue: 0xF8 / 255)
    static let greyLight = Color(red: 0xF0 / 255, green: 0xEF / 255, blue: 0xEC / 255)
    static let inkLight = Color(red: 0x14 / 255, green: 0x13 / 255, blue: 0x12 / 255)
    static let ink2Light = Color(red: 0x3A / 255, green: 0x2E / 255, blue: 0x12 / 255)
    static let subLight = Color(red: 0x5C / 255, green: 0x5A / 255, blue: 0x54 / 255)
    static let mutedLight = Color(red: 0x8B / 255, green: 0x88 / 255, blue: 0x80 / 255)
    static let faintLight = Color(red: 0xB9 / 255, green: 0xAF / 255, blue: 0xA0 / 255)
    static let lineLight = Color(red: 0xED / 255, green: 0xE6 / 255, blue: 0xD7 / 255)

    // Dark — near-black charcoal with a hint of warmth, not sepia brown
    static let paperDark = Color(red: 0x13 / 255, green: 0x12 / 255, blue: 0x11 / 255)
    static let greyDark = Color(red: 0x1C / 255, green: 0x1B / 255, blue: 0x1A / 255)
    static let inkDark = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xF1 / 255)
    static let ink2Dark = Color(red: 0xE4 / 255, green: 0xE2 / 255, blue: 0xDE / 255)
    static let subDark = Color(red: 0xC4 / 255, green: 0xC2 / 255, blue: 0xBE / 255)
    static let mutedDark = Color(red: 0x94 / 255, green: 0x92 / 255, blue: 0x8E / 255)
    static let faintDark = Color(red: 0x5E / 255, green: 0x5C / 255, blue: 0x59 / 255)
    static let lineDark = Color.white.opacity(0.10)
    static let surfaceLight = Color.white
    static let surfaceDark = Color(red: 0x32 / 255, green: 0x31 / 255, blue: 0x30 / 255)

    static let paperLightRGB = (253.0 / 255, 251.0 / 255, 248.0 / 255)
    static let greyLightRGB = (240.0 / 255, 239.0 / 255, 236.0 / 255)
    static let paperDarkRGB = (19.0 / 255, 18.0 / 255, 17.0 / 255)
    static let greyDarkRGB = (28.0 / 255, 27.0 / 255, 26.0 / 255)

    struct Theme {
        var paper: Color
        var grey: Color
        var surface: Color
        var ink: Color
        var ink2: Color
        var sub: Color
        var muted: Color
        var faint: Color
        var line: Color
        var shadowSoft: Color
        var shadowLift: Color
        var cardHairline: Color
        var isDark: Bool
    }

    static func theme(_ scheme: ColorScheme) -> Theme {
        if scheme == .dark {
            return Theme(
                paper: paperDark,
                grey: greyDark,
                surface: surfaceDark,
                ink: inkDark,
                ink2: ink2Dark,
                sub: subDark,
                muted: mutedDark,
                faint: faintDark,
                line: lineDark,
                shadowSoft: Color.white.opacity(0.04),
                shadowLift: Color.white.opacity(0.07),
                cardHairline: Color.white.opacity(0.07),
                isDark: true
            )
        }
        return Theme(
            paper: paperLight,
            grey: greyLight,
            surface: surfaceLight,
            ink: inkLight,
            ink2: ink2Light,
            sub: subLight,
            muted: mutedLight,
            faint: faintLight,
            line: lineLight,
            shadowSoft: Color.black.opacity(0.025),
            shadowLift: Color.black.opacity(0.06),
            cardHairline: Color.black.opacity(0.05),
            isDark: false
        )
    }
}
