import Foundation
import ImageIO

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    static let maximumPixelSize = 420

    private let memoryStore = MemoryStore()
    private var inFlightTasks: [UUID: Task<CGImage?, Never>] = [:]

    init() {}

    /// Synchronous lock-free read from NSCache (documented thread-safe by Apple) so cards
    /// render already-decoded thumbnails on frame 0 without a placeholder flash.
    nonisolated func cachedThumbnail(for id: UUID) -> CGImage? {
        memoryStore.image(for: id)
    }

    nonisolated func evict(ids: [UUID]) {
        for id in ids {
            memoryStore.remove(for: id)
        }
    }

    nonisolated func clear() {
        memoryStore.removeAll()
    }

    func thumbnail(for record: ClipboardRecord) async -> CGImage? {
        guard !Task.isCancelled, let data = record.imageData else { return nil }
        if let image = memoryStore.image(for: record.id) {
            return image
        }

        if let existingTask = inFlightTasks[record.id] {
            return await existingTask.value
        }

        let id = record.id
        let store = memoryStore
        let decodeTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
            Self.decodeThumbnail(from: data)
        }
        inFlightTasks[id] = decodeTask

        let image = await decodeTask.value
        inFlightTasks[id] = nil

        if let image {
            store.store(image, for: id)
        }
        return Task.isCancelled ? nil : image
    }

    private nonisolated static func decodeThumbnail(from data: Data) -> CGImage? {
        autoreleasepool {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(
                    data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                  ),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary),
                  !Task.isCancelled
            else { return nil }
            return image
        }
    }
}

private final class MemoryStore: @unchecked Sendable {
    private let cache = NSCache<NSUUID, CGImage>()

    init() {
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for id: UUID) -> CGImage? {
        cache.object(forKey: id as NSUUID)
    }

    func store(_ image: CGImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID, cost: image.bytesPerRow * image.height)
    }

    func remove(for id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
