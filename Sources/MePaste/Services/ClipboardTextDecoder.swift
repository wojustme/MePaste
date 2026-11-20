import AppKit

enum ClipboardTextDecoder {
    static func plainText(from payloads: [ClipboardPayload]) -> String? {
        let items = Dictionary(grouping: payloads, by: \.itemIndex)
        guard !items.isEmpty else { return nil }

        var texts: [String] = []
        for index in items.keys.sorted() {
            guard let item = items[index], let text = plainText(fromItem: item) else {
                // Never silently discard a file or image in a mixed-item copy.
                return nil
            }
            texts.append(text)
        }
        return texts.joined(separator: "\n")
    }

    private static func plainText(fromItem payloads: [ClipboardPayload]) -> String? {
        for (type, encoding) in [
            (NSPasteboard.PasteboardType.string.rawValue, String.Encoding.utf8),
            ("public.utf16-plain-text", .utf16),
            (NSPasteboard.PasteboardType.URL.rawValue, .utf8)
        ] {
            if let data = payloads.first(where: { $0.type == type })?.data,
               let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        if let data = payloads.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data {
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        }

        // HTML normally comes with a plain-text representation. Do not load HTML
        // through WebKit here: importing it can fetch remote resources and is not
        // safe on the background record-building actor.
        return nil
    }
}
