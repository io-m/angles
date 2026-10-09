import Foundation

/// Which angle each For you card opens on, so two cards in a row never open on the
/// same one when either can avoid it.
///
/// Order is the server's and never changes here; only the face does. A card keeps the
/// angle it came with unless that repeats the card above (or a fixed card below), and
/// then takes another angle it actually has. A card never opens on an angle you hearted
/// while it has one you have not. Your own cards keep the cover you saved,
/// and a card with one angle keeps it: a repeat beats dropping a card.
enum ForYouCovers {
    /// - Parameters:
    ///   - cards: the cards entering the shelf, top to bottom.
    ///   - above: the face of the card already shown just above them, if any.
    ///   - below: the face of the card already shown just below them, if any.
    static func assign(_ cards: [HomeCard], above: Style? = nil, below: Style? = nil) -> [HomeCard] {
        var faced = cards
        var previous = above
        for index in faced.indices {
            let next = faced.indices.contains(index + 1) ? faced[index + 1] : nil
            // A neighbour below that cannot change is a hard constraint; one that can
            // will step aside on its own turn, so it is only a preference.
            let fixedBelow: Style?
            let softBelow: Style?
            if let next {
                fixedBelow = isFixed(next) ? next.spotlightStyle : nil
                softBelow = isFixed(next) ? nil : next.spotlightStyle
            } else {
                fixedBelow = below
                softBelow = nil
            }
            faced[index].spotlightStyle = face(
                for: faced[index],
                previous: previous,
                fixedBelow: fixedBelow,
                softBelow: softBelow
            )
            previous = faced[index].spotlightStyle
        }
        return faced
    }

    private static func isFixed(_ card: HomeCard) -> Bool {
        card.isOwner || choices(for: card).count < 2
    }

    private static func styles(of card: HomeCard) -> [Style] {
        var seen: Set<Style> = []
        return card.slides.map(\.result.style).filter { seen.insert($0).inserted }
    }

    /// The angles a card may open on. One you already hearted is in your library, so the
    /// card opens on one you have not read whenever it has one, even if that repeats a
    /// neighbour.
    private static func choices(for card: HomeCard) -> [Style] {
        let available = styles(of: card)
        let kept = Set(card.slides.filter(\.isHearted).map(\.result.style))
        let unkept = available.filter { !kept.contains($0) }
        return unkept.isEmpty ? available : unkept
    }

    private static func face(
        for card: HomeCard,
        previous: Style?,
        fixedBelow: Style?,
        softBelow: Style?
    ) -> Style {
        let current = card.spotlightStyle
        guard !card.isOwner, styles(of: card).count > 1 else {
            return current
        }
        let options = choices(for: card)
        if options.contains(current), current != previous, current != fixedBelow {
            return current
        }

        // Stable order: the angles after the current one, wrapping, so the same card
        // always lands on the same replacement.
        let start = Style.allCases.firstIndex(of: current) ?? 0
        let cycle = (1 ... Style.allCases.count).map {
            Style.allCases[(start + $0) % Style.allCases.count]
        }
        let ordered = cycle.filter(options.contains)
        let tiers: [(Style) -> Bool] = [
            { $0 != previous && $0 != fixedBelow && $0 != softBelow },
            { $0 != previous && $0 != fixedBelow },
            { $0 != previous },
        ]
        for tier in tiers {
            if let pick = ordered.first(where: tier) {
                return pick
            }
        }
        return options.contains(current) ? current : options[0]
    }
}
