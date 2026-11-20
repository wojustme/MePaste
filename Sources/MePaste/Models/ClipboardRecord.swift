import AppKit
import Foundation
import ImageIO

struct ClipboardPayload: Codable, Hashable, Sendable {
    let itemIndex: Int
    let type: String
    let data: Data
}

struct ClipboardRecord: Codable, Identifiable, Hashable, Sendable {
    static let previewCharacterLimit = 2_000
    private static let titleCharacterLimit = 160

    let id: UUID
    let createdAt: Date
    let payloads: [ClipboardPayload]
    var isFavorite: Bool

    // Records are immutable. Build presentation/search data once, off the main actor,
    // rather than decoding payloads every time SwiftUI evaluates a card or a filter.
    let plainText: String?
    let plainTextForPasting: String?
    let fileURLs: [URL]
    let imageData: Data?
    let kind: ClipboardKind
    let title: String
    let subtitle: String
    let previewText: String?
    let isPreviewTruncated: Bool
    private let searchableText: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        payloads: [ClipboardPayload],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.payloads = payloads
        self.isFavorite = isFavorite

        let plainTextForPasting = ClipboardTextDecoder.plainText(from: payloads)
        let plainText = plainTextForPasting
            ?? payloads.first { $0.type == NSPasteboard.PasteboardType.string.rawValue }
                .flatMap { String(data: $0.data, encoding: .utf8) }
        let fileURLs = payloads
            .filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            .compactMap { String(data: $0.data, encoding: .utf8) }
            .compactMap(URL.init(string:))
        let image = Self.imageMetadata(in: payloads)
        let fileNames = fileURLs.map(\.lastPathComponent)
        let characterCount = plainText?.count ?? 0

        self.plainText = plainText
        self.plainTextForPasting = plainTextForPasting
        self.fileURLs = fileURLs
        imageData = image?.data
        isPreviewTruncated = characterCount > Self.previewCharacterLimit
        previewText = plainText.map {
            characterCount > Self.previewCharacterLimit
                ? String($0.prefix(Self.previewCharacterLimit)) + "…"
                : $0
        }

        if let image {
            kind = .image
            title = "图片"
            subtitle = "\(image.width) × \(image.height)"
        } else if !fileURLs.isEmpty {
            kind = .files
            title = Self.abbreviated(fileNames.joined(separator: ", "))
            subtitle = "\(fileURLs.count) 个文件"
        } else if let plainText {
            kind = .text
            let firstLine = plainText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix { !$0.isNewline }
            title = firstLine.isEmpty ? "空文本" : Self.abbreviated(String(firstLine))
            subtitle = "\(characterCount) 个字符"
        } else {
            kind = .other
            title = "其他内容"
            subtitle = Self.abbreviated(payloads.map(\.type).joined(separator: ", "))
        }

        searchableText = ClipboardSearchQuery.fold([
            title,
            subtitle,
            plainText ?? "",
            fileNames.joined(separator: " "),
            payloads.map(\.type).joined(separator: " ")
        ].joined(separator: " "))
    }

    // Favoriting is additive metadata. Old records decode as ordinary history;
    // presentation/search caches still never belong on disk.
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, payloads, isFavorite
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            payloads: try container.decode([ClipboardPayload].self, forKey: .payloads),
            isFavorite: try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(payloads, forKey: .payloads)
        if isFavorite {
            try container.encode(true, forKey: .isFavorite)
        }
    }

    static func == (lhs: ClipboardRecord, rhs: ClipboardRecord) -> Bool {
        lhs.id == rhs.id && lhs.createdAt == rhs.createdAt
            && lhs.payloads == rhs.payloads && lhs.isFavorite == rhs.isFavorite
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(createdAt)
        hasher.combine(payloads)
        hasher.combine(isFavorite)
    }

    func payload(for type: NSPasteboard.PasteboardType) -> Data? {
        payloads.first { $0.type == type.rawValue }?.data
    }

    func matchesSearch(_ query: String) -> Bool {
        matchesSearch(ClipboardSearchQuery(query))
    }

    func matchesSearch(_ query: ClipboardSearchQuery) -> Bool {
        query.isEmpty || searchableText.contains(query.text)
    }

    func hasSameContent(as other: ClipboardRecord) -> Bool {
        payloads == other.payloads || Set(payloads) == Set(other.payloads)
    }

    private static func abbreviated(_ text: String) -> String {
        let prefix = text.prefix(titleCharacterLimit)
        return prefix.endIndex == text.endIndex ? text : String(prefix) + "…"
    }

    private static func imageMetadata(
        in payloads: [ClipboardPayload]
    ) -> (data: Data, width: Int, height: Int)? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = payloads.first(where: { $0.type == type.rawValue })?.data,
                  let source = CGImageSourceCreateWithData(
                    data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                  ),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0
            else { continue }
            return (data, width, height)
        }
        return nil
    }
}

struct ClipboardSearchQuery: Equatable, Sendable {
    let text: String

    init(_ text: String) {
        self.text = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var isEmpty: Bool { text.isEmpty }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

enum ClipboardKind: String, Sendable {
    case text
    case image
    case files
    case other

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .files:
            return "doc.on.doc"
        case .other:
            return "clipboard"
        }
    }
}
