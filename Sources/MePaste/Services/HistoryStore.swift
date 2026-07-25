import Foundation

actor HistoryStore {
    private let directoryURL: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directoryURL = applicationSupport.appendingPathComponent("MePaste", isDirectory: true)
        indexURL = directoryURL.appendingPathComponent("history.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load() throws -> [ClipboardRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }
        return try decoder.decode([ClipboardRecord].self, from: Data(contentsOf: indexURL))
    }

    func save(_ records: [ClipboardRecord]) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: .atomic)
    }
}
