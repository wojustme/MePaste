import CryptoKit
import Foundation

actor HistoryStore {
    /// Payloads at or above this threshold (e.g., images, large rich documents) are stored
    /// once as content-addressed binary blobs so saving text edits never re-encodes megabytes
    /// of base64 image data into `history.json`.
    static let externalBlobThresholdBytes = 64 * 1024

    private let directoryURL: URL
    private let indexURL: URL
    private let blobsDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.directoryURL = directoryURL
            ?? applicationSupport.appendingPathComponent("MePaste", isDirectory: true)
        indexURL = self.directoryURL.appendingPathComponent("history.json")
        blobsDirectoryURL = self.directoryURL.appendingPathComponent("blobs", isDirectory: true)

        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func load() throws -> [ClipboardRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }
        let rawData = try Data(contentsOf: indexURL, options: .mappedIfSafe)
        let storedRecords = try decoder.decode([StoredRecord].self, from: rawData)
        return storedRecords.compactMap { stored in
            let payloads = stored.payloads.compactMap { entry -> ClipboardPayload? in
                if let inlineData = entry.data {
                    return ClipboardPayload(itemIndex: entry.itemIndex, type: entry.type, data: inlineData)
                }
                if let blobKey = entry.blob {
                    let blobURL = blobsDirectoryURL.appendingPathComponent(blobKey)
                    guard let blobData = try? Data(contentsOf: blobURL) else { return nil }
                    return ClipboardPayload(itemIndex: entry.itemIndex, type: entry.type, data: blobData)
                }
                return nil
            }
            guard !payloads.isEmpty else { return nil }
            return ClipboardRecord(
                id: stored.id,
                createdAt: stored.createdAt,
                payloads: payloads,
                isFavorite: stored.isFavorite ?? false
            )
        }
    }

    func save(_ records: [ClipboardRecord]) throws {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var referencedBlobs: Set<String> = []
        var createdBlobsDirectory = false

        var storedRecords: [StoredRecord] = []
        storedRecords.reserveCapacity(records.count)

        for record in records {
            try Task.checkCancellation()
            var storedPayloads: [StoredPayload] = []
            storedPayloads.reserveCapacity(record.payloads.count)

            for payload in record.payloads {
                if payload.data.count >= Self.externalBlobThresholdBytes {
                    if !createdBlobsDirectory {
                        try fileManager.createDirectory(at: blobsDirectoryURL, withIntermediateDirectories: true)
                        createdBlobsDirectory = true
                    }
                    let blobKey = Self.blobKey(for: payload.data)
                    referencedBlobs.insert(blobKey)
                    let blobURL = blobsDirectoryURL.appendingPathComponent(blobKey)
                    if !fileManager.fileExists(atPath: blobURL.path) {
                        try payload.data.write(to: blobURL, options: .atomic)
                    }
                    storedPayloads.append(
                        StoredPayload(itemIndex: payload.itemIndex, type: payload.type, data: nil, blob: blobKey)
                    )
                } else {
                    storedPayloads.append(
                        StoredPayload(itemIndex: payload.itemIndex, type: payload.type, data: payload.data, blob: nil)
                    )
                }
            }

            storedRecords.append(
                StoredRecord(
                    id: record.id,
                    createdAt: record.createdAt,
                    payloads: storedPayloads,
                    isFavorite: record.isFavorite ? true : nil
                )
            )
        }

        let data = try encoder.encode(storedRecords)
        try Task.checkCancellation()
        try data.write(to: indexURL, options: .atomic)

        pruneUnusedBlobs(keeping: referencedBlobs, fileManager: fileManager)
    }

    private func pruneUnusedBlobs(keeping referencedBlobs: Set<String>, fileManager: FileManager) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: blobsDirectoryURL.path) else {
            return
        }
        for name in entries where !referencedBlobs.contains(name) {
            try? fileManager.removeItem(at: blobsDirectoryURL.appendingPathComponent(name))
        }
    }

    private static func blobKey(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined() + ".bin"
    }
}

private struct StoredRecord: Codable {
    let id: UUID
    let createdAt: Date
    let payloads: [StoredPayload]
    let isFavorite: Bool?
}

private struct StoredPayload: Codable {
    let itemIndex: Int
    let type: String
    let data: Data?
    let blob: String?
}
