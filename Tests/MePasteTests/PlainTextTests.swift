import AppKit
import Foundation
import Testing
@testable import MePaste

struct PlainTextTests {
    @Test func testMultipleTextItemsBecomeNewlineSeparatedInOriginalOrder() {
        let payloads = [
            ClipboardPayload(itemIndex: 2, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("third".utf8)),
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("first".utf8)),
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>first</b>".utf8)),
            ClipboardPayload(itemIndex: 1, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("second".utf8))
        ]
        let record = ClipboardRecord(payloads: payloads)
        #expect(record.plainTextForPasting == "first\nsecond\nthird")
        #expect(record.plainText == record.plainTextForPasting)
        #expect(record.matchesSearch("third"))
    }

    @Test func testRTFOnlyRecordCanBePastedAndSearchedAsPlainText() {
        let rtf = Data(#"{\rtf1\ansi Hello \b world\b0 !}"#.utf8)
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf)
        ])
        #expect(record.plainTextForPasting == "Hello world!")
        #expect(record.matchesSearch("hello world"))
        #expect(record.payload(for: .rtf) == rtf)
    }

    @Test func testEmptyTextRemainsValidPlainText() {
        #expect(textRecord("").plainTextForPasting == "")
        #expect(textRecord(" \n ").plainTextForPasting == " \n ")
    }

    @Test func testMixedTextAndFileCannotSilentlyDropFile() {
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("text".utf8)),
            ClipboardPayload(itemIndex: 1, type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/example.txt".utf8))
        ])
        #expect(record.plainTextForPasting == nil)
    }

    @Test func testUnsupportedHTMLOnlyRecordDoesNotLoadRemoteResources() {
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<img src='https://example.invalid/secret'><p>text</p>".utf8))
        ])
        #expect(record.plainTextForPasting == nil)
    }

    @Test func testFavoriteMetadataRoundTripsWithoutPersistingDerivedText() throws {
        var record = textRecord("favorite")
        record.isFavorite = true
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClipboardRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.isFavorite)
        #expect(decoded.plainTextForPasting == "favorite")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "createdAt", "payloads", "isFavorite"])
    }
}

@MainActor
struct PlainTextClipboardTests {
    @Test func testPlainTextWriteHasOnlyStringTypeAndDoesNotRecapture() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, frontmostApplicationIdentifier: { nil })
        defer { monitor.stop(); pasteboard.releaseGlobally() }
        var captures = 0
        monitor.onNewRecord = { _ in captures += 1 }
        monitor.start()
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("text".utf8)),
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>text</b>".utf8))
        ])
        #expect(monitor.write(record, asPlainText: true))
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.pasteboardItems?.first?.types == [.string])
        monitor.checkForChanges()
        try await Task.sleep(for: .milliseconds(20))
        #expect(captures == 0)
    }

    @Test func testUnsupportedPlainTextDoesNotClearExistingPasteboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep", forType: .string)
        let previousChangeCount = pasteboard.changeCount
        #expect(!monitor.write(ClipboardRecord(payloads: [try imagePayload()]), asPlainText: true))
        #expect(pasteboard.string(forType: .string) == "keep")
        #expect(pasteboard.changeCount == previousChangeCount)
    }
}
