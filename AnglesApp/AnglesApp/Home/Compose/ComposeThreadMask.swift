import SwiftUI

/// Where the header ends and the bottom bar starts, in screen coordinates, plus the bar's own
/// height. Held in a reference so a keyboard sliding (a new value every frame) redraws only the
/// thread's mask, never the thread.
@Observable
final class ComposeEdges {
    var header: CGFloat = 119
    var bottom: CGFloat = 0
    /// The bar's own height (input, Post, or the held place), so the thread's last row stops above it.
    var barHeight: CGFloat = ComposeLayout.bottomBarHeight
}

/// The gradient stops of the thread's mask, as fractions of its height.
struct ThreadMaskStops: Equatable {
    static let topFade: CGFloat = 20
    static let bottomFade: CGFloat = 36
    /// What is scrolled under the bar stays faintly visible.
    static let belowBarOpacity = 0.14

    var topStart: CGFloat
    var topEnd: CGFloat
    var bottomStart: CGFloat
    var bottomEnd: CGFloat
    /// Opacity from `bottomEnd` down: the 14% shade under the bar, or solid when there is no bar edge.
    var belowOpacity: Double

    /// `height` and `minY` are the mask's own size and top in screen coordinates; `header` and
    /// `bottom` are `ComposeEdges` (a `bottom` of 0 means the bar has not reported yet).
    static func compute(height rawHeight: CGFloat, minY: CGFloat, header: CGFloat, bottom: CGFloat) -> ThreadMaskStops {
        let height = max(rawHeight, 1)
        let topEnd = min(max(header / height, 0.02), 0.5)
        let topStart = max(topEnd - topFade / height, 0.005)
        let bottomEnd = bottom > 0
            ? min(max((bottom - minY) / height, topEnd + 0.01), 1)
            : 1
        let bottomStart = max(bottomEnd - bottomFade / height, topEnd + 0.005)
        return ThreadMaskStops(
            topStart: topStart,
            topEnd: topEnd,
            bottomStart: bottomStart,
            bottomEnd: bottomEnd,
            belowOpacity: bottomEnd < 1 ? belowBarOpacity : 1
        )
    }
}

/// The thread dissolves under the header and, mirrored, just above the bottom bar, so a bubble
/// never reaches the input: it is gone before it gets there. It reads the edges itself, so only
/// this view redraws when they move.
struct ComposeThreadMask: View {
    let edges: ComposeEdges

    var body: some View {
        GeometryReader { geo in
            let stops = ThreadMaskStops.compute(
                height: geo.size.height,
                minY: geo.frame(in: .global).minY,
                header: edges.header,
                bottom: edges.bottom
            )
            let below = Color.black.opacity(stops.belowOpacity)

            LinearGradient(
                stops: [
                    // Nothing is drawn under the header buttons: no text over text.
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: stops.topStart),
                    .init(color: .black, location: stops.topEnd),
                    .init(color: .black, location: stops.bottomStart),
                    .init(color: below, location: stops.bottomEnd),
                    .init(color: below, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
