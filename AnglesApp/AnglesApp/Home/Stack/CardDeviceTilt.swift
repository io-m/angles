import CoreMotion
import SwiftUI

/// Timestamp-based low-pass for the tilt targets: real elapsed time sets how far
/// each sample moves, a soft dead-zone keeps a still hand still, and a per-sample
/// slew cap means no single sample — however late or bunched — can jump the mark.
struct CardTiltFilter: Equatable {
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0

    /// How long the filtered value takes to close most of the gap to its target.
    static let timeConstant: TimeInterval = 0.16
    /// Gaps and pauses longer than this count as one ordinary sample interval.
    static let maximumStepTime: TimeInterval = 0.05
    /// The largest change one sample may make, so hand tremor arrives as a glide.
    static let maximumStep: Double = 0.05
    /// Targets inside this band around neutral count as neutral.
    static let deadZone: Double = 0.08

    mutating func ingest(targetRoll: Double, targetPitch: Double, dt: TimeInterval) {
        let clampedDT = min(max(dt, 0), Self.maximumStepTime)
        guard clampedDT > 0 else { return }
        let alpha = 1 - exp(-clampedDT / Self.timeConstant)
        roll = Self.step(from: roll, toward: Self.softDeadZone(targetRoll), alpha: alpha)
        pitch = Self.step(from: pitch, toward: Self.softDeadZone(targetPitch), alpha: alpha)
    }

    private static func step(from: Double, toward target: Double, alpha: Double) -> Double {
        let diff = target - from
        if abs(diff) <= 0.002 {
            return target
        }
        let delta = diff * alpha
        return from + min(max(delta, -maximumStep), maximumStep)
    }

    private static func softDeadZone(_ value: Double) -> Double {
        let magnitude = abs(value)
        guard magnitude > deadZone else { return 0 }
        return (value < 0 ? -1 : 1) * (magnitude - deadZone) / (1 - deadZone)
    }
}

/// Where a roll/pitch puts the corner mark. Pure, so the behind and top cards are
/// guaranteed to place the mark identically for the same tilt. Travel and rotation
/// are a fifth smaller than the last size: present, never showy.
enum CardTiltGeometry {
    /// Share of the previous travel and turn that still moves.
    static let motion: CGFloat = 0.8

    static func markOffset(roll: CGFloat, pitch: CGFloat) -> CGSize {
        CGSize(width: 30 + roll * 32 * motion, height: 26 + pitch * 26 * motion)
    }

    static func markRotation(roll: CGFloat) -> Double {
        -12 + Double(roll) * 13 * Double(motion)
    }
}

/// Gravity on the stack cards. A natural hold sits near zero; tilting the phone
/// moves the light and the corner mark. The same idea as AppSail's featured wash,
/// driven by the phone instead of a timer.
@MainActor
@Observable
final class CardDeviceTilt {
    struct Pose: Equatable {
        var roll: CGFloat = 0
        var pitch: CGFloat = 0
    }

    private(set) var pose = Pose()

    /// -1...1. Positive when the right side of the phone is lower.
    var roll: CGFloat { pose.roll }
    /// -1...1. Positive when the screen tips face-down from a natural hold.
    var pitch: CGFloat { pose.pitch }

    /// Set during an active card drag or fling so sensor samples never compete with 120Hz gestures.
    @ObservationIgnored var isPaused = false
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var filter = CardTiltFilter()
    @ObservationIgnored private var lastTimestamp: TimeInterval?
    @ObservationIgnored private var running = false

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        lastTimestamp = nil
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        // Updates already arrive on the main queue, so ingest in place: a fresh
        // unstructured Task per sample only lets samples queue behind drag frames
        // and then discharge in a bunch.
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let x = motion.gravity.x
            let z = motion.gravity.z
            let timestamp = motion.timestamp
            MainActor.assumeIsolated {
                self.ingest(x: x, z: z, timestamp: timestamp)
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        lastTimestamp = nil
        manager.stopDeviceMotionUpdates()
    }

    /// Device gravity: +x is the phone's right, +z is out of the screen.
    /// A comfortable portrait hold already tips the screen back, so pitch is measured from there.
    func ingest(x: Double, z: Double, timestamp: TimeInterval) {
        let dt = lastTimestamp.map { timestamp - $0 } ?? (1.0 / 30.0)
        lastTimestamp = timestamp
        guard !isPaused else { return }
        let targetRoll = min(1, max(-1, x / 0.32))
        let targetPitch = min(1, max(-1, (z - (-0.42)) / 0.32))
        filter.ingest(targetRoll: targetRoll, targetPitch: targetPitch, dt: dt)
        let nextRoll = CGFloat(filter.roll)
        let nextPitch = CGFloat(filter.pitch)
        let rollChanged = abs(nextRoll - pose.roll) >= 0.004 || (nextRoll == 0 && pose.roll != 0)
        let pitchChanged = abs(nextPitch - pose.pitch) >= 0.004 || (nextPitch == 0 && pose.pitch != 0)
        guard rollChanged || pitchChanged else { return }
        pose = Pose(
            roll: rollChanged ? nextRoll : pose.roll,
            pitch: pitchChanged ? nextPitch : pose.pitch
        )
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
        let axis = Self.axis(degrees: 135 + roll * 27)
        let shiftX = roll * 0.42
        let shiftY = pitch * 0.37
        LinearGradient(
            stops: [
                .init(color: ink.opacity(0.018 * presence), location: 0),
                .init(color: ink.opacity(0.036 * presence), location: 0.46),
                .init(color: ink.opacity(0.104 * presence), location: 1)
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
        let offset = CardTiltGeometry.markOffset(roll: roll, pitch: pitch)
        Image(systemName: systemImage)
            .font(.system(size: AngleCardMetrics.watermarkSize, weight: .semibold))
            .foregroundStyle(ink.opacity(fade))
            .rotationEffect(.degrees(CardTiltGeometry.markRotation(roll: roll)))
            .offset(x: offset.width, y: offset.height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: systemImage)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
