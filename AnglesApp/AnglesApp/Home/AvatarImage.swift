import ImageIO
import SwiftUI
import UIKit

/// Decodes straight to a thumbnail, so a camera photo never inflates to full size in memory.
enum ImageDownsampler {
    static func image(from data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: thumbnail, scale: 1, orientation: .up)
    }
}

/// Author photos, decoded once at the size a card shows them and kept in memory, so a row
/// scrolling back into view does not refetch or flash its initials.
enum AvatarImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    static func cached(_ url: URL, pixelSize: Int) -> UIImage? {
        cache.object(forKey: key(url, pixelSize))
    }

    static func load(_ url: URL, pixelSize: Int) async -> UIImage? {
        if let hit = cached(url, pixelSize: pixelSize) {
            return hit
        }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = ImageDownsampler.image(from: data, maxPixelSize: pixelSize)
        else {
            return nil
        }
        cache.setObject(image, forKey: key(url, pixelSize))
        return image
    }

    private static func key(_ url: URL, _ pixelSize: Int) -> NSString {
        "\(pixelSize)|\(url.absoluteString)" as NSString
    }
}

/// A remote author photo sized to `side`. Shows nothing until it is ready.
struct RemoteAvatarImage: View {
    let url: URL
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    private var pixelSize: Int {
        max(1, Int((side * displayScale).rounded(.up)))
    }

    var body: some View {
        let image = loaded ?? AvatarImages.cached(url, pixelSize: pixelSize)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            }
        }
        .task(id: "\(pixelSize)|\(url.absoluteString)") {
            guard image == nil else {
                return
            }
            loaded = await AvatarImages.load(url, pixelSize: pixelSize)
        }
    }
}
