import SwiftUI
import WidgetKit

/// Home-screen widgets always render as light cards with dark copy, independent of system appearance.
private enum AnglesWidgetPalette {
    static let brand = Color(red: 0.968, green: 0.451, blue: 0.037)
    static let ink = Color(red: 0x14 / 255, green: 0x13 / 255, blue: 0x12 / 255)
    static let inkMuted = Color(red: 0x3A / 255, green: 0x2E / 255, blue: 0x12 / 255).opacity(0.72)
    static let composePaper = [
        Color(red: 0xFD / 255, green: 0xFB / 255, blue: 0xF8 / 255),
        Color(red: 0xF0 / 255, green: 0xEB / 255, blue: 0xE2 / 255),
    ]
}

@main
struct AnglesWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoriteAngleWidget()
        WriteThoughtWidget()
    }
}

private struct FavoriteAngleEntry: TimelineEntry {
    let date: Date
    let item: FavoriteAngleWidgetItem?
}

private struct FavoriteAngleProvider: TimelineProvider {
    /// WidgetKit may coalesce display updates, but prebuilding short timeline entries gives
    /// favorites a frequent rotation without waking the app or spending background budget.
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> FavoriteAngleEntry {
        FavoriteAngleEntry(date: Date(), item: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoriteAngleEntry) -> Void) {
        let item = WidgetSnapshotStore()?.loadFavoriteAngles().items.first
            ?? (context.isPreview ? .placeholder : nil)
        completion(FavoriteAngleEntry(date: Date(), item: item))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteAngleEntry>) -> Void) {
        let now = Date()
        let items = WidgetSnapshotStore()?.loadFavoriteAngles().items ?? []
        guard !items.isEmpty else {
            let entry = FavoriteAngleEntry(date: now, item: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
            return
        }

        let startingIndex = Int(now.timeIntervalSince1970 / Self.refreshInterval) % items.count
        let entries = (0 ..< 24).map { offset in
            FavoriteAngleEntry(
                date: now.addingTimeInterval(Double(offset) * Self.refreshInterval),
                item: items[(startingIndex + offset) % items.count]
            )
        }
        completion(
            Timeline(
                entries: entries,
                policy: .after(now.addingTimeInterval(24 * Self.refreshInterval))
            )
        )
    }
}

private struct FavoriteAngleView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavoriteAngleEntry

    var body: some View {
        Group {
            if let item = entry.item {
                content(item)
            } else {
                emptyState
            }
        }
        .environment(\.colorScheme, family == .accessoryRectangular ? .dark : .light)
        .foregroundStyle(family == .accessoryRectangular ? Color.white : AnglesWidgetPalette.ink)
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                AccessoryWidgetBackground()
            } else {
                background(for: entry.item?.style)
            }
        }
        .widgetURL(AnglesWidgetConstants.favoritesURL)
    }

    @ViewBuilder
    private func content(_ item: FavoriteAngleWidgetItem) -> some View {
        if family == .accessoryRectangular {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.styleDisplayName)
                        .font(.caption2.weight(.semibold))
                    Text(item.answer)
                        .font(.caption)
                        .lineLimit(2)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
                AnglesWidgetBrandMark(size: 14, emphasis: .accessory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
                HStack(spacing: 6) {
                    Image(systemName: styleSymbol(item.style))
                    Text(item.styleDisplayName)
                    Spacer(minLength: 0)
                    if let lifeAreaLabel = item.lifeAreaLabel, family == .systemMedium {
                        Text(lifeAreaLabel)
                            .foregroundStyle(AnglesWidgetPalette.inkMuted)
                    }
                    AnglesWidgetBrandMark(size: family == .systemSmall ? 16 : 18, emphasis: .home)
                }
                .font(.caption.weight(.semibold))

                Text(item.answer)
                    .font(answerFont(for: item.answer))
                    .lineLimit(answerLineLimit(for: item.answer))
                    .minimumScaleFactor(0.76)
                    .privacySensitive()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var emptyState: some View {
        VStack(alignment: family == .accessoryRectangular ? .leading : .center, spacing: 6) {
            AnglesWidgetBrandMark(
                size: family == .accessoryRectangular ? 16 : 22,
                emphasis: family == .accessoryRectangular ? .accessory : .home
            )
            Text("Heart an angle to keep it close.")
                .font(.caption.weight(.medium))
                .foregroundStyle(family == .accessoryRectangular ? Color.white : AnglesWidgetPalette.ink)
                .multilineTextAlignment(family == .accessoryRectangular ? .leading : .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func background(for style: String?) -> some View {
        LinearGradient(
            colors: styleColors(style),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func styleColors(_ style: String?) -> [Color] {
        switch style {
        case "optimistic":
            return [Color(red: 0.98, green: 0.91, blue: 0.65), Color(red: 0.97, green: 0.82, blue: 0.58)]
        case "humorous":
            return [Color(red: 0.88, green: 0.91, blue: 0.72), Color(red: 0.73, green: 0.86, blue: 0.70)]
        case "tough_love":
            return [Color(red: 0.96, green: 0.76, blue: 0.67), Color(red: 0.88, green: 0.64, blue: 0.60)]
        default:
            return [Color(red: 0.77, green: 0.87, blue: 0.91), Color(red: 0.66, green: 0.78, blue: 0.84)]
        }
    }

    private func styleSymbol(_ style: String) -> String {
        switch style {
        case "optimistic": return "sun.max.fill"
        case "humorous": return "face.smiling.fill"
        case "tough_love": return "flame.fill"
        default: return "mountain.2.fill"
        }
    }

    private func answerFont(for answer: String) -> Font {
        if family == .systemSmall {
            if answer.count > 145 {
                return .caption.weight(.medium)
            }
            if answer.count > 100 {
                return .footnote.weight(.medium)
            }
            return .callout.weight(.medium)
        }
        if answer.count > 155 {
            return .footnote.weight(.medium)
        }
        if answer.count > 110 {
            return .callout.weight(.medium)
        }
        return .body.weight(.medium)
    }

    private func answerLineLimit(for answer: String) -> Int {
        if family == .systemSmall {
            if answer.count > 145 {
                return 10
            }
            if answer.count > 100 {
                return 8
            }
            return 6
        }
        return answer.count > 155 ? 7 : 6
    }
}

struct FavoriteAngleWidget: Widget {
    let kind = AnglesWidgetConstants.favoriteWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavoriteAngleProvider()) { entry in
            FavoriteAngleView(entry: entry)
        }
        .configurationDisplayName("Favorite Angle")
        .description("Keep an angle you hearted close by.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct WriteThoughtEntry: TimelineEntry {
    let date: Date
}

private struct WriteThoughtProvider: TimelineProvider {
    func placeholder(in context: Context) -> WriteThoughtEntry {
        WriteThoughtEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WriteThoughtEntry) -> Void) {
        completion(WriteThoughtEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WriteThoughtEntry>) -> Void) {
        completion(Timeline(entries: [WriteThoughtEntry(date: Date())], policy: .never))
    }
}

private struct WriteThoughtView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    AnglesWidgetBrandMark(size: 42, emphasis: .accessory)
                }
            case .accessoryRectangular:
                HStack(spacing: 7) {
                    AnglesWidgetBrandMark(size: 18, emphasis: .accessory)
                    Text("Break the spiral")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            default:
                VStack(spacing: 10) {
                    AnglesWidgetBrandMark(size: 46, emphasis: .home)
                    Text("Break the spiral")
                        .font(.headline)
                        .foregroundStyle(AnglesWidgetPalette.ink)
                        .multilineTextAlignment(.center)
                    Text("Write a thought")
                        .font(.caption)
                        .foregroundStyle(AnglesWidgetPalette.inkMuted)
                }
                .environment(\.colorScheme, .light)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular:
                AccessoryWidgetBackground()
            default:
                LinearGradient(
                    colors: AnglesWidgetPalette.composePaper,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .widgetURL(AnglesWidgetConstants.composeURL)
        .accessibilityLabel("Write a thought in Angles")
    }
}

private enum AnglesWidgetBrandMarkEmphasis {
    /// Home-screen widget on the warm paper card.
    case home
    /// Lock Screen accessory plate: darker back, brighter front, like the orange icon.
    case accessory
}

/// Two-layer mark with the same orange gradients as the app icon (`InspireMark`).
/// Laid out at the requested size so WidgetKit never archives a 1024pt canvas.
private struct AnglesWidgetBrandMark: View {
    let size: CGFloat
    var emphasis: AnglesWidgetBrandMarkEmphasis = .home

    private static let canvas: CGFloat = 1024

    var body: some View {
        ZStack {
            placedLayer(
                "InspireMarkBack",
                style: backGradient,
                width: 777,
                height: 754,
                scale: 0.9,
                translation: CGSize(width: 45, height: 13)
            )
            placedLayer(
                "InspireMarkFront",
                style: frontGradient,
                width: 775,
                height: 771,
                scale: 0.9,
                translation: CGSize(width: -49.66155, height: -5.3726)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func placedLayer(
        _ name: String,
        style: LinearGradient,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        translation: CGSize
    ) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(
                width: size * width / Self.canvas,
                height: size * height / Self.canvas
            )
            .scaleEffect(scale)
            .offset(
                x: size * translation.width / Self.canvas,
                y: size * translation.height / Self.canvas
            )
            .foregroundStyle(style)
    }

    private var backGradient: LinearGradient {
        switch emphasis {
        case .home:
            return LinearGradient(
                colors: [
                    Color(red: 1, green: 0.712, blue: 0),
                    Color(red: 0.968, green: 0.451, blue: 0.037),
                ],
                startPoint: UnitPoint(x: 0.10, y: 0),
                endPoint: UnitPoint(x: 0.78, y: 1)
            )
        case .accessory:
            // Same stops as the orange body: brighter at the top-left, deeper at the bottom-right.
            return LinearGradient(
                colors: [Color(white: 0.62), Color(white: 0.34)],
                startPoint: UnitPoint(x: 0.10, y: 0),
                endPoint: UnitPoint(x: 0.78, y: 1)
            )
        }
    }

    private var frontGradient: LinearGradient {
        switch emphasis {
        case .home:
            return LinearGradient(
                colors: [
                    Color(red: 1, green: 0.789, blue: 0.370).opacity(0.9),
                    Color(red: 1, green: 0.578, blue: 0),
                ],
                startPoint: UnitPoint(x: 0.13, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            )
        case .accessory:
            // Same stops as the gold highlight: brighter than the back, with a visible falloff.
            return LinearGradient(
                colors: [Color.white, Color(white: 0.82)],
                startPoint: UnitPoint(x: 0.13, y: 0),
                endPoint: UnitPoint(x: 1, y: 1)
            )
        }
    }
}

struct WriteThoughtWidget: Widget {
    let kind = "WriteThoughtWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WriteThoughtProvider()) { _ in
            WriteThoughtView()
        }
        .configurationDisplayName("Write a Thought")
        .description("Open Angles and break the spiral.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private extension FavoriteAngleWidgetItem {
    static let placeholder = FavoriteAngleWidgetItem(
        id: "placeholder-stoic",
        cardID: "placeholder",
        answer: "Name what is yours to influence, and let the rest stop borrowing your attention.",
        style: "stoic",
        styleDisplayName: "Stoic",
        lifeAreaLabel: "Self-worth",
        favoritedAt: Date()
    )
}
