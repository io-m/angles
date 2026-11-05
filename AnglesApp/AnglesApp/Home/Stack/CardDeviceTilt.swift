import CoreMotion
import SwiftUI

/// Gravity on the top stack card. A natural hold sits near zero; tilting the phone
/// moves the light and the corner mark. The same idea as AppSail's featured wash,
/// driven by the phone instead of a timer.
@MainActor
@Observable
final class CardDeviceTilt {
    /// -1...1. Positive when the right side of the phone is lower.
    private(set) var roll: CGFloat = 0
    /// -1...1. Positive when the screen tips face-down from a natural hold.
    private(set) var pitch: CGFloat = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var filteredRoll = 0.0
    @ObservationIgnored private var filteredPitch = 0.0
    @ObservationIgnored private var running = false

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let x = motion.gravity.x
            let z = motion.gravity.z
            Task { @MainActor [weak self] in
                self?.ingest(x: x, z: z)
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
    }

    /// Device gravity: +x is the phone's right, +z is out of the screen.
    /// A comfortable portrait hold already tips the screen back, so pitch is measured from there.
    private func ingest(x: Double, z: Double) {
        let targetRoll = min(1, max(-1, x / 0.32))
        let targetPitch = min(1, max(-1, (z - (-0.42)) / 0.32))
        filteredRoll += (targetRoll - filteredRoll) * 0.34
        filteredPitch += (targetPitch - filteredPitch) * 0.34
        let nextRoll = CGFloat(filteredRoll)
        let nextPitch = CGFloat(filteredPitch)
        if abs(nextRoll - roll) >= 0.012 {
            roll = nextRoll
        }
        if abs(nextPitch - pitch) >= 0.012 {
            pitch = nextPitch
        }
    }
}

/// Diagonal style wash. At rest it matches a featured card: dim at the top-left,
/// stronger at the bottom-right. Tilting slides and turns that diagonal.
struct CardTiltWash: View {
    let ink: Color
    var tilt: CardDeviceTilt

    var body: some View {
        let roll = Double(tilt.roll)
        let pitch = Double(tilt.pitch)
        let presence = 0.7 + 0.3 * max(abs(roll), abs(pitch))
        let axis = Self.axis(degrees: 135 + roll * 36)
        let shiftX = roll * 0.55
        let shiftY = pitch * 0.48
        LinearGradient(
            stops: [
                .init(color: ink.opacity(0.03 * presence), location: 0),
                .init(color: ink.opacity(0.06 * presence), location: 0.46),
                .init(color: ink.opacity(0.18 * presence), location: 1)
            ],
            startPoint: UnitPoint(
                x: CGFloat(0.5 - axis.dx * 0.75 + shiftX),
                y: CGFloat(0.5 - axis.dy * 0.75 + shiftY)
            ),
            endPoint: UnitPoint(
                x: CGFloat(0.5 + axis.dx * 0.75 + shiftX),
                y: CGFloat(0.5 + axis.dy * 0.75 + shiftY)
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// CSS degrees, clockwise from up, in a y-down unit square. 135° is the bottom-right.
    private static func axis(degrees: Double) -> (dx: Double, dy: Double) {
        let radians = degrees * .pi / 180
        return (sin(radians), -cos(radians))
    }
}

/// The faded style mark in the bottom-right. It slides and turns with the phone.
struct CardTiltMark: View {
    let systemImage: String
    let ink: Color
    var tilt: CardDeviceTilt?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let roll: CGFloat = reduceMotion ? 0 : (tilt?.roll ?? 0)
        let pitch: CGFloat = reduceMotion ? 0 : (tilt?.pitch ?? 0)
        let fade = colorScheme == .dark ? 0.20 : 0.12
        Image(systemName: systemImage)
            .font(.system(size: AngleCardMetrics.watermarkSize, weight: .semibold))
            .foregroundStyle(ink.opacity(fade))
            .rotationEffect(.degrees(-12 + Double(roll) * 18))
            .offset(x: 30 + roll * 42, y: 26 + pitch * 34)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: systemImage)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
