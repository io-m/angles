import Lottie
import SwiftUI

/// One unzip of the ride per appearance, started while the answer is on screen, shared with
/// the cover. The dark file is the same animation recolored by `scripts/lottie-dark-variant.mjs`.
@MainActor
enum SaveRide {
    private static var loading: [Bool: Task<DotLottieFile?, Never>] = [:]

    static func preload(dark: Bool) async {
        _ = await load(dark: dark)
    }

    static func load(dark: Bool) async -> DotLottieFile? {
        if let task = loading[dark] {
            return await task.value
        }
        let name = dark ? "Go to school dark" : "Go to school"
        let task = Task { try? await DotLottieFile.named(name) }
        loading[dark] = task
        return await task.value
    }

    /// Drops the unzipped files once the cover is gone; the next answer preloads again.
    static func release() {
        loading.removeAll()
    }
}

struct SaveCelebrationCover: View {
    let label: String
    var playsAnimation: Bool
    var safeAreaInsets: EdgeInsets
    var size: CGSize

    @Environment(\.colorScheme) private var colorScheme

    /// The file is a 1200 square. The rider occupies x 228...900, y 424...1029, so the
    /// artboard center is empty sky. These bounds are the bike, which is what we center.
    private static let canvas: CGFloat = 1200
    private static let scene = CGRect(x: 228, y: 424, width: 672, height: 605)

    var body: some View {
        let safeWidth = max(size.width - safeAreaInsets.leading - safeAreaInsets.trailing, 1)
        let safeHeight = max(size.height - safeAreaInsets.top - safeAreaInsets.bottom, 1)
        let sceneAspect = Self.scene.width / Self.scene.height
        let targetWidth = min(safeWidth * 0.86, safeHeight * 0.58 * sceneAspect)
        let side = targetWidth * (Self.canvas / Self.scene.width)
        let sceneCenter = CGPoint(
            x: Self.scene.midX / Self.canvas * side,
            y: Self.scene.midY / Self.canvas * side
        )
        let screenCenter = CGPoint(
            x: safeAreaInsets.leading + safeWidth / 2,
            y: safeAreaInsets.top + safeHeight / 2
        )

        ZStack {
            StyleWash.headerGlassFill(fromInk: .clear, toInk: .clear, progress: 0)

            if playsAnimation {
                let dark = colorScheme == .dark
                LottieView {
                    await SaveRide.load(dark: dark)
                }
                .playing()
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .id(dark)
                .position(
                    x: screenCenter.x - (sceneCenter.x - side / 2),
                    y: screenCenter.y - (sceneCenter.y - side / 2)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onDisappear { SaveRide.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("save.cover")
    }
}
