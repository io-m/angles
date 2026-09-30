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

    /// Icon Composer canvas. Layer scale and translation match `Angles.icon`.
    private static let canvas: CGFloat = 1024
    /// Ink width of both layers on that canvas, so `size` is the mark, not the empty margin.
    private static let inkWidth: CGFloat = 792.48

    var body: some View {
        ZStack {
            placedLayer(
                "InspireMarkBack",
                style: backStyle,
                width: 777,
                height: 754,
                scale: 0.9,
                translation: CGSize(width: 45, height: 13)
            )
            placedLayer(
                "InspireMarkFront",
                style: frontStyle,
                width: 775,
                height: 771,
                scale: 0.9,
                translation: CGSize(width: -49.66155, height: -5.3726)
            )
        }
        .frame(width: Self.canvas, height: Self.canvas)
        .scaleEffect(size / Self.inkWidth)
        .frame(width: size, height: size)
    }

    private func placedLayer(
        _ name: String,
        style: AnyShapeStyle,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        translation: CGSize
    ) -> some View {
        Image(name)
            .resizable()
            .frame(width: width, height: height)
            .scaleEffect(scale)
            .offset(translation)
            .foregroundStyle(style)
    }

    private var backStyle: AnyShapeStyle {
        switch rendering {
        case .brand:
            AnyShapeStyle(backGradient)
        case .monochrome(let color):
            AnyShapeStyle(color)
        }
    }

    private var frontStyle: AnyShapeStyle {
        switch rendering {
        case .brand:
            AnyShapeStyle(frontGradient)
        case .monochrome(let color):
            AnyShapeStyle(color)
        }
    }

    private var backGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 1, green: 0.663, blue: 0.144),
                    Color(red: 0.968, green: 0.480, blue: 0),
                ],
                startPoint: UnitPoint(x: 0.30, y: 0),
                endPoint: UnitPoint(x: 0.73, y: 1)
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 1, green: 0.712, blue: 0),
                Color(red: 0.968, green: 0.451, blue: 0.037),
            ],
            startPoint: UnitPoint(x: 0.10, y: 0),
            endPoint: UnitPoint(x: 0.78, y: 1)
        )
    }

    private var frontGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1, green: 0.789, blue: 0.370).opacity(colorScheme == .dark ? 1 : 0.9),
                Color(red: 1, green: 0.578, blue: 0),
            ],
            startPoint: UnitPoint(x: 0.13, y: 0),
            endPoint: UnitPoint(x: 1, y: 1)
        )
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
