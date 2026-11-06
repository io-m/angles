import SwiftUI

/// Two-layer mark from `Angles.icon`, aligned with the app icon layout.
struct InspireMark: View {
    enum Rendering {
        case brand
        case monochrome(Color)
    }

    var size: CGFloat = 24
    var rendering: Rendering = .brand

    /// The mark's deep orange, for glows that stand in for Angles itself.
    static let brandColor = Color(red: 0.968, green: 0.451, blue: 0.037)

    @Environment(\.colorScheme) private var colorScheme

    /// Ink width of both layers on that canvas, so `size` is the mark, not the empty margin.
    private static let inkWidth: CGFloat = 792.48

    var body: some View {
        let ratio = size / Self.inkWidth
        ZStack {
            placedLayer(
                "InspireMarkBack",
                gradient: backGradient,
                width: 777 * 0.9 * ratio,
                height: 754 * 0.9 * ratio,
                translation: CGSize(width: 45 * ratio, height: 13 * ratio)
            )
            placedLayer(
                "InspireMarkFront",
                gradient: frontGradient,
                width: 775 * 0.9 * ratio,
                height: 771 * 0.9 * ratio,
                translation: CGSize(width: -49.66155 * ratio, height: -5.3726 * ratio)
            )
        }
        .frame(width: size, height: size)
    }

    private func placedLayer(
        _ name: String,
        gradient: LinearGradient,
        width: CGFloat,
        height: CGFloat,
        translation: CGSize
    ) -> some View {
        Image(name)
            .resizable()
            .frame(width: width, height: height)
            .offset(translation)
            .foregroundStyle(gradient)
    }

    private var backGradient: LinearGradient {
        switch rendering {
        case .brand:
            brandBackGradient
        case .monochrome(let color):
            monochromeBackGradient(color)
        }
    }

    private var frontGradient: LinearGradient {
        switch rendering {
        case .brand:
            brandFrontGradient
        case .monochrome(let color):
            monochromeFrontGradient(color)
        }
    }

    private func monochromeBackGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.75), color.opacity(0.4)],
            startPoint: UnitPoint(x: 0.10, y: 0),
            endPoint: UnitPoint(x: 0.78, y: 1)
        )
    }

    private func monochromeFrontGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.82)],
            startPoint: UnitPoint(x: 0.13, y: 0),
            endPoint: UnitPoint(x: 1, y: 1)
        )
    }

    private static let brandBackDark = LinearGradient(
        colors: [
            Color(red: 1, green: 0.663, blue: 0.144),
            Color(red: 0.968, green: 0.480, blue: 0),
        ],
        startPoint: UnitPoint(x: 0.30, y: 0),
        endPoint: UnitPoint(x: 0.73, y: 1)
    )

    private static let brandBackLight = LinearGradient(
        colors: [
            Color(red: 1, green: 0.712, blue: 0),
            Color(red: 0.968, green: 0.451, blue: 0.037),
        ],
        startPoint: UnitPoint(x: 0.10, y: 0),
        endPoint: UnitPoint(x: 0.78, y: 1)
    )

    private static let brandFrontDark = LinearGradient(
        colors: [
            Color(red: 1, green: 0.789, blue: 0.370),
            Color(red: 1, green: 0.578, blue: 0),
        ],
        startPoint: UnitPoint(x: 0.13, y: 0),
        endPoint: UnitPoint(x: 1, y: 1)
    )

    private static let brandFrontLight = LinearGradient(
        colors: [
            Color(red: 1, green: 0.789, blue: 0.370).opacity(0.9),
            Color(red: 1, green: 0.578, blue: 0),
        ],
        startPoint: UnitPoint(x: 0.13, y: 0),
        endPoint: UnitPoint(x: 1, y: 1)
    )

    private var brandBackGradient: LinearGradient {
        colorScheme == .dark ? Self.brandBackDark : Self.brandBackLight
    }

    private var brandFrontGradient: LinearGradient {
        colorScheme == .dark ? Self.brandFrontDark : Self.brandFrontLight
    }
}

struct InspireMarkCircle: View {
    var fill: Color
    var markSize: CircleIcon.Size = .normal
    var hairline: Color? = nil
    var rendering: InspireMark.Rendering = .brand

    var body: some View {
        InspireMark(size: markSize.side * 0.46, rendering: rendering)
            .frame(width: markSize.side, height: markSize.side)
            .background(fill, in: Circle())
            .overlay {
                if let hairline {
                    Circle().strokeBorder(hairline, lineWidth: 0.5)
                }
            }
            .contentShape(Circle())
    }
}
