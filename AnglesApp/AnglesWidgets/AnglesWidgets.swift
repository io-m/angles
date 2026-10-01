import SwiftUI
import WidgetKit

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
        .containerBackground(for: .widget) {
            background(for: entry.item?.style)
        }
        .widgetURL(AnglesWidgetConstants.favoritesURL)
    }

    @ViewBuilder
    private func content(_ item: FavoriteAngleWidgetItem) -> some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.styleDisplayName)
                    .font(.caption2.weight(.semibold))
                Text(item.answer)
                    .font(.caption)
                    .lineLimit(2)
                    .privacySensitive()
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
                            .foregroundStyle(.secondary)
                    }
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
            Image(systemName: "heart")
                .font(.title3)
            Text("Heart an angle to keep it close.")
                .font(.caption.weight(.medium))
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
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    AnglesWidgetMark(size: 27)
                }
            } else if family == .accessoryRectangular {
                HStack(spacing: 7) {
                    AnglesWidgetMark(size: 18)
                    Text("Break the spiral")
                        .font(.headline)
                }
            } else {
                VStack(spacing: 10) {
                    AnglesWidgetMark(size: 42)
                    Text("Break the spiral")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Write a thought")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.88),
                    Color(red: 0.89, green: 0.85, blue: 0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(AnglesWidgetConstants.composeURL)
        .accessibilityLabel("Write a thought in Angles")
    }
}

private struct AnglesWidgetMark: View {
    let size: CGFloat

    var body: some View {
        Image("AnglesMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
