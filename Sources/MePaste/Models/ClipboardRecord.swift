import AppKit
import CryptoKit
import Foundation
import ImageIO

struct ClipboardPayload: Codable, Hashable, Sendable {
    let itemIndex: Int
    let type: String
    let data: Data
}

struct ClipboardColorValue: Equatable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let hex: String

    init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hexDigits = String(trimmed.dropFirst())
        guard hexDigits.count == 3 || hexDigits.count == 6 || hexDigits.count == 8,
              hexDigits.allSatisfy(\.isHexDigit)
        else { return nil }

        let expanded: String
        if hexDigits.count == 3 {
            expanded = hexDigits.map { "\($0)\($0)" }.joined() + "FF"
        } else if hexDigits.count == 6 {
            expanded = hexDigits + "FF"
        } else {
            expanded = hexDigits
        }

        guard let value = UInt32(expanded, radix: 16) else { return nil }
        red = Double((value >> 24) & 0xFF) / 255.0
        green = Double((value >> 16) & 0xFF) / 255.0
        blue = Double((value >> 8) & 0xFF) / 255.0
        alpha = Double(value & 0xFF) / 255.0
        hex = "#" + hexDigits.uppercased()
    }
}

struct ClipboardRecord: Codable, Identifiable, Hashable, Sendable {
    static let previewCharacterLimit = 2_000
    static let cardPreviewCharacterLimit = 420
    private static let titleCharacterLimit = 160

    let id: UUID
    let createdAt: Date
    let payloads: [ClipboardPayload]
    var isFavorite: Bool

    // Records are immutable. Build presentation/search/dedup data once, off the main actor,
    // rather than decoding payloads every time SwiftUI evaluates a card or a filter.
    let plainText: String?
    let plainTextForPasting: String?
    let fileURLs: [URL]
    let imageData: Data?
    let kind: ClipboardKind
    let title: String
    let subtitle: String
    let previewText: String?
    let cardPreviewText: String?
    let isPreviewTruncated: Bool
    let detectedURL: URL?
    let detectedColor: ClipboardColorValue?
    let isCodeLike: Bool
    let totalPayloadBytes: Int
    private let contentDigest: Data
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
        cardPreviewText = plainText.map(Self.makeCardPreview)
        totalPayloadBytes = payloads.reduce(0) { $0 + $1.data.count }
        contentDigest = Self.computeContentDigest(for: payloads)

        if let image {
            kind = .image
            title = "图片"
            subtitle = "\(image.width) × \(image.height)"
            detectedURL = nil
            detectedColor = nil
            isCodeLike = false
        } else if !fileURLs.isEmpty {
            kind = .files
            title = Self.abbreviated(fileNames.joined(separator: ", "))
            subtitle = "\(fileURLs.count) 个文件"
            detectedURL = nil
            detectedColor = nil
            isCodeLike = false
        } else if let plainText {
            kind = .text
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.prefix { !$0.isNewline }
            title = firstLine.isEmpty ? "空文本" : Self.abbreviated(String(firstLine))
            subtitle = "\(characterCount) 个字符"
            detectedURL = Self.detectWebURL(in: trimmed)
            detectedColor = trimmed.count <= 9 ? ClipboardColorValue(parsing: trimmed) : nil
            isCodeLike = detectedURL == nil && detectedColor == nil && Self.looksLikeCode(cardPreviewText ?? "")
        } else {
            kind = .other
            title = "其他内容"
            subtitle = Self.abbreviated(payloads.map(\.type).joined(separator: ", "))
            detectedURL = nil
            detectedColor = nil
            isCodeLike = false
        }

        searchableText = ClipboardSearchQuery.fold([
            title,
            subtitle,
            plainText ?? "",
            fileNames.joined(separator: " "),
            payloads.map(\.type).joined(separator: " ")
        ].joined(separator: " "))
    }

    private init(copying record: ClipboardRecord, createdAt: Date) {
        id = record.id
        self.createdAt = createdAt
        payloads = record.payloads
        isFavorite = record.isFavorite
        plainText = record.plainText
        plainTextForPasting = record.plainTextForPasting
        fileURLs = record.fileURLs
        imageData = record.imageData
        kind = record.kind
        title = record.title
        subtitle = record.subtitle
        previewText = record.previewText
        cardPreviewText = record.cardPreviewText
        isPreviewTruncated = record.isPreviewTruncated
        detectedURL = record.detectedURL
        detectedColor = record.detectedColor
        isCodeLike = record.isCodeLike
        totalPayloadBytes = record.totalPayloadBytes
        contentDigest = record.contentDigest
        searchableText = record.searchableText
    }

    /// Returns a copy with an updated timestamp without re-decoding payloads or hashes.
    func touched(at date: Date = Date()) -> ClipboardRecord {
        ClipboardRecord(copying: self, createdAt: date)
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
        lhs.id == rhs.id
            && lhs.createdAt == rhs.createdAt
            && lhs.isFavorite == rhs.isFavorite
            && lhs.totalPayloadBytes == rhs.totalPayloadBytes
            && lhs.contentDigest == rhs.contentDigest
            && lhs.payloads == rhs.payloads
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(createdAt)
        hasher.combine(contentDigest)
        hasher.combine(isFavorite)
    }

    func payload(for type: NSPasteboard.PasteboardType) -> Data? {
        payloads.first { $0.type == type.rawValue }?.data
    }

    func matchesSearch(_ query: String) -> Bool {
        matchesSearch(ClipboardSearchQuery(query))
    }

    func matchesSearch(_ query: ClipboardSearchQuery) -> Bool {
        if query.isEmpty { return true }
        if query.tokens.count <= 1 {
            return searchableText.contains(query.text)
        }
        return query.tokens.allSatisfy { searchableText.contains($0) }
    }

    func hasSameContent(as other: ClipboardRecord) -> Bool {
        guard totalPayloadBytes == other.totalPayloadBytes,
              payloads.count == other.payloads.count,
              contentDigest == other.contentDigest
        else { return false }
        if payloads == other.payloads { return true }
        return payloads.count > 1 && Set(payloads) == Set(other.payloads)
    }

    private static func computeContentDigest(for payloads: [ClipboardPayload]) -> Data {
        guard !payloads.isEmpty else { return Data() }
        if payloads.count == 1, let single = payloads.first {
            return digest(of: single)
        }
        var perPayloadDigests = payloads.map(digest(of:))
        perPayloadDigests.sort { $0.lexicographicallyPrecedes($1) }
        var combined = SHA256()
        for part in perPayloadDigests {
            combined.update(data: part)
        }
        return Data(combined.finalize())
    }

    private static func digest(of payload: ClipboardPayload) -> Data {
        var hasher = SHA256()
        var index = payload.itemIndex.littleEndian
        withUnsafeBytes(of: &index) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(payload.type.utf8))
        var separator: UInt8 = 0
        withUnsafeBytes(of: &separator) { hasher.update(bufferPointer: $0) }
        hasher.update(data: payload.data)
        return Data(hasher.finalize())
    }

    private static func makeCardPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let prefix = trimmed.prefix(cardPreviewCharacterLimit)
        return prefix.endIndex == trimmed.endIndex ? trimmed : String(prefix) + "…"
    }

    private static func detectWebURL(in trimmed: String) -> URL? {
        guard trimmed.count <= 2_048,
              trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        guard text.count >= 8 else { return false }
        let markers = ["{", "}", "=>", "->", "func ", "import ", "const ", "let ", "var ", "def ", "class ", "return ", "SELECT ", "</"]
        var score = 0
        for marker in markers where text.contains(marker) {
            score += 1
            if score >= 2 { return true }
        }
        return text.hasPrefix("git ") || text.hasPrefix("curl ") || text.hasPrefix("swift ") || text.hasPrefix("npm ")
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
    let tokens: [String]

    init(_ text: String) {
        let folded = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        self.text = folded
        self.tokens = folded.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { text.isEmpty }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

enum ClipboardKind: String, CaseIterable, Sendable {
    case text
    case image
    case files
    case other

    var title: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .files: return "文件"
        case .other: return "其他"
        }
    }

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
