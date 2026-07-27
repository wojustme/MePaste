import AppKit
import Foundation

struct ClipboardPayload: Codable, Hashable {
    let itemIndex: Int
    let type: String
    let data: Data
}

struct ClipboardRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let payloads: [ClipboardPayload]

    init(id: UUID = UUID(), createdAt: Date = Date(), payloads: [ClipboardPayload]) {
        self.id = id
        self.createdAt = createdAt
        self.payloads = payloads
    }

    var plainText: String? {
        payload(for: .string).flatMap { String(data: $0, encoding: .utf8) }
    }

    var fileURLs: [URL] {
        payloads
            .filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            .compactMap { String(data: $0.data, encoding: .utf8) }
            .compactMap(URL.init(string:))
    }

    var image: NSImage? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in preferredTypes {
            if let data = payload(for: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    var kind: ClipboardKind {
        if image != nil {
            return .image
        }
        if !fileURLs.isEmpty {
            return .files
        }
        if plainText != nil {
            return .text
        }
        return .other
    }

    var title: String {
        switch kind {
        case .text:
            return plainText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "空文本"
        case .image:
            return "图片"
        case .files:
            let names = fileURLs.map(\.lastPathComponent)
            return names.isEmpty ? "文件" : names.joined(separator: ", ")
        case .other:
            return "其他内容"
        }
    }

    var subtitle: String {
        switch kind {
        case .text:
            return "\(plainText?.count ?? 0) 个字符"
        case .image:
            guard let size = image?.size else { return "图片" }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .files:
            return "\(fileURLs.count) 个文件"
        case .other:
            return payloads.map(\.type).joined(separator: ", ")
        }
    }

    func payload(for type: NSPasteboard.PasteboardType) -> Data? {
        payloads.first { $0.type == type.rawValue }?.data
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        let searchableText = [
            title,
            subtitle,
            plainText,
            fileURLs.map(\.lastPathComponent).joined(separator: " "),
            payloads.map(\.type).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return searchableText.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    func hasSameContent(as other: ClipboardRecord) -> Bool {
        Set(payloads) == Set(other.payloads)
    }
}

enum ClipboardKind: String {
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
