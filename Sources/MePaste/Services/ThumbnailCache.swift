import Foundation
import ImageIO

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    static let maximumPixelSize = 420

    private let cache = NSCache<NSUUID, CGImage>()

    init() {
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func thumbnail(for record: ClipboardRecord) -> CGImage? {
        guard !Task.isCancelled, let data = record.imageData else { return nil }
        let key = record.id as NSUUID
        if let image = cache.object(forKey: key) {
            return image
        }

        return autoreleasepool {
            guard let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary), !Task.isCancelled else { return nil }

            cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
            return image
        }
    }
}
