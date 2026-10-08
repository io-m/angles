import Foundation
import QuartzCore

/// DEBUG-only frame timer. Prints `HITCH <ms>` for every frame that took clearly longer than the
/// display's frame interval, and a `FRAMES` summary every 5 seconds of motion. Read it from
/// `devicectl device process launch --console`. Release builds compile it out.
enum FrameMonitor {
    #if DEBUG
    @MainActor private static var link: CADisplayLink?
    @MainActor private static let probe = Probe()

    @MainActor
    static func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: probe, selector: #selector(Probe.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private final class Probe: NSObject {
        private var last: CFTimeInterval = 0
        private var frames = 0
        private var hitches = 0
        private var worst: Double = 0
        private var windowStart: CFTimeInterval = 0

        @objc func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            defer { last = now }
            guard last > 0 else { windowStart = now; return }
            let interval = link.targetTimestamp - link.timestamp
            let delta = now - last
            // Idle screens deliver no frames; ignore gaps longer than half a second.
            guard delta < 0.5 else { windowStart = now; return }
            frames += 1
            if delta > interval * 1.5 {
                hitches += 1
                worst = max(worst, delta)
                print("HITCH \(Int(delta * 1000))ms")
            }
            if now - windowStart >= 5 {
                print("FRAMES \(frames) hitches=\(hitches) worst=\(Int(worst * 1000))ms")
                frames = 0; hitches = 0; worst = 0; windowStart = now
            }
        }
    }
    #else
    @inline(__always)
    static func start() {}
    #endif
}
