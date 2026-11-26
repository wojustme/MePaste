import AppKit
import Foundation
import Testing
@testable import MePaste

struct ClipboardRecordTests {
    @Test func testSearchIgnoresCaseDiacriticsAndSurroundingWhitespace() {
        let record = textRecord("CAFÉ résumé\n剪贴板历史")
        #expect(record.matchesSearch("  cafe  "))
        #expect(record.matchesSearch("RESUME"))
        #expect(record.matchesSearch("剪贴板"))
        #expect(record.matchesSearch(" \n "))
        #expect(!record.matchesSearch("missing"))
    }

    @Test func testLongTextPreviewIsBoundedWithoutTruncatingPayloadOrSearch() {
        let text = String(repeating: "长文本🙂", count: 10_000) + "unique-search-tail"
        let record = textRecord(text)
        #expect(record.isPreviewTruncated)
        #expect(record.previewText?.count == ClipboardRecord.previewCharacterLimit + 1)
        #expect(record.title.count <= 161)
        #expect(record.plainText == text)
        #expect(record.payload(for: .string) == Data(text.utf8))
        #expect(record.matchesSearch("UNIQUE-search-TAIL"))
        #expect(record.subtitle == "\(text.count) 个字符")
    }

    @Test func testTextTitleUsesFirstNonemptyLineAndShortPreviewIsUnchanged() {
        let record = textRecord(" \n标题\n正文\n")
        #expect(record.kind == .text)
        #expect(record.title == "标题")
        #expect(record.previewText == record.plainText)
        #expect(!record.isPreviewTruncated)
        #expect(textRecord("\n \t").title == "空文本")
    }

    @Test func testImageMetadataDoesNotRequireFullSizeImageForPresentation() throws {
        let record = ClipboardRecord(payloads: [try imagePayload()])
        #expect(record.kind == .image)
        #expect(record.title == "图片")
        #expect(record.subtitle == "1200 × 600")
        #expect(record.imageData != nil)
        #expect(record.matchesSearch("1200"))
        #expect(record.matchesSearch("PUBLIC.PNG"))
    }

    @Test func testInvalidImageFallsBackToText() {
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.png.rawValue, data: Data()),
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("fallback".utf8))
        ])
        #expect(record.kind == .text)
        #expect(record.imageData == nil)
        #expect(record.title == "fallback")
    }

    @Test func testFileNamesRemainSearchable() {
        let record = ClipboardRecord(payloads: ["file:///tmp/Caf%C3%A9.txt", "file:///tmp/report.pdf"].enumerated().map {
            ClipboardPayload(itemIndex: $0.offset, type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data($0.element.utf8))
        })
        #expect(record.kind == .files)
        #expect(record.fileURLs.count == 2)
        #expect(record.subtitle == "2 个文件")
        #expect(record.matchesSearch("CAFE.TXT"))
        #expect(record.matchesSearch("report.pdf"))
    }

    @Test func testLegacyJSONRoundTripExcludesDerivedCaches() throws {
        let original = textRecord("历史数据 Café")
        let legacyData = try JSONSerialization.data(withJSONObject: [[
            "id": original.id.uuidString,
            "createdAt": original.createdAt.timeIntervalSinceReferenceDate,
            "payloads": original.payloads.map {
                ["itemIndex": $0.itemIndex, "type": $0.type, "data": $0.data.base64EncodedString()] as [String: Any]
            }
        ]])
        let decoded = try JSONDecoder().decode([ClipboardRecord].self, from: legacyData)
        #expect(decoded == [original])
        #expect(decoded[0].matchesSearch("CAFE"))
        let encoded = try JSONEncoder().encode(decoded)
        let objects = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(Set(objects[0].keys) == ["id", "createdAt", "payloads"])
    }

    @Test func testDeduplicationIgnoresPayloadOrderingButNotItemIndexes() {
        let first = textRecord("text").payloads[0]
        let second = ClipboardPayload(itemIndex: 0, type: "public.html", data: Data("<p>text</p>".utf8))
        let record = ClipboardRecord(payloads: [first, second])
        #expect(record.hasSameContent(as: ClipboardRecord(payloads: [second, first])))
        #expect(!record.hasSameContent(as: ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 1, type: first.type, data: first.data), second
        ])))
    }

    @Test func testMultiTokenSearchMatchesOutOfOrderTerms() {
        let record = textRecord("swift build --configuration release")
        #expect(record.matchesSearch("swift release"))
        #expect(record.matchesSearch("release swift"))
        #expect(!record.matchesSearch("swift debug"))
    }

    @Test func testDetectsWebURLsHexColorsAndCodeSnippets() {
        let linkRecord = textRecord("https://apple.com/macos")
        #expect(linkRecord.detectedURL?.host == "apple.com")
        #expect(linkRecord.detectedColor == nil)

        let colorRecord = textRecord("#3b82f6")
        #expect(colorRecord.detectedColor?.hex == "#3B82F6")
        #expect(colorRecord.detectedURL == nil)

        let shortColor = textRecord("#f0a")
        #expect(shortColor.detectedColor?.hex == "#F0A")

        let codeRecord = textRecord("func greet() -> String { return \"hi\" }")
        #expect(codeRecord.isCodeLike)
    }
}
