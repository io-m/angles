import Foundation

/// DEBUG-only body counter. Put `let _ = RenderCounter.hit("Name")` at the top of a `body` and read
/// `RENDER Name n` lines from `devicectl device process launch --console`. Release builds compile it out.
enum RenderCounter {
    #if DEBUG
    @MainActor private static var counts: [String: Int] = [:]

    @MainActor
    static func hit(_ name: String) {
        counts[name, default: 0] += 1
        print("RENDER \(name) \(counts[name] ?? 0)")
    }
    #else
    @inline(__always)
    static func hit(_ name: String) {}
    #endif
}
