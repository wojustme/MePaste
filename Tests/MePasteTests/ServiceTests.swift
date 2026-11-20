import AppKit
import Foundation
import Testing
@testable import MePaste

struct ServiceTests {
    @Test func testThumbnailIsDownsampledAndReused() async throws {
        let record = ClipboardRecord(payloads: [try imagePayload()])
        let cache = ThumbnailCache()
        let first = await cache.thumbnail(for: record)
        let image = try #require(first)
        #expect(image.width == ThumbnailCache.maximumPixelSize)
        #expect(image.height == ThumbnailCache.maximumPixelSize / 2)
        let second = await cache.thumbnail(for: record)
        #expect(first === second)
        #expect(record.imageData == record.payload(for: .png))
    }

    @Test func testTextHasNoThumbnail() async {
        #expect(await ThumbnailCache().thumbnail(for: textRecord("text")) == nil)
    }

    @Test func testHistoryStoreRoundTripAndEmptyHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory)
        #expect(try await store.load().isEmpty)
        let records = [textRecord("Café"), ClipboardRecord(payloads: [try imagePayload()])]
        try await store.save(records)
        let loaded = try await store.load()
        #expect(loaded == records)
        #expect(loaded[0].matchesSearch("cafe"))
        #expect(loaded[1].subtitle == "1200 × 600")
        try await store.save([])
        #expect(try await store.load().isEmpty)
    }

    @Test func testHistoryStoreRejectsCancelledSaveWithoutOverwritingExistingHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directoryURL: directory)
        let original = [textRecord("keep")]
        try await store.save(original)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.save([])
        }
        do {
            try await task.value
            Issue.record("A cancelled save should throw")
        } catch is CancellationError {
            // Expected.
        }
        #expect(try await store.load() == original)
    }

    @Test func testSearchFindsFullContentInLargeHistory() async {
        let records = (0..<500).map {
            textRecord(String(repeating: "preview ", count: 300) + "needle-\($0)")
        }
        let results = await HistorySearch().filter(records, matching: ClipboardSearchQuery("needle-499"))
        #expect(results.map(\.id) == [records[499].id])
    }
}

@MainActor
struct ClipboardMonitorTests {
    @Test func testChangedPasteboardIsCapturedOnlyOnceAndOwnWritesAreIgnored() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        defer { monitor.stop(); pasteboard.releaseGlobally() }
        var records: [ClipboardRecord] = []
        monitor.onNewRecord = { records.append($0) }
        monitor.start()
        pasteboard.clearContents()
        #expect(pasteboard.setString("captured", forType: .string))
        monitor.checkForChanges()
        monitor.checkForChanges()
        try await waitUntil { records.count == 1 }
        #expect(records.first?.plainText == "captured")
        monitor.write(textRecord("own write"))
        monitor.checkForChanges()
        try await Task.sleep(for: .milliseconds(50))
        #expect(records.count == 1)
        #expect(pasteboard.string(forType: .string) == "own write")
    }

    @Test func testConcealedContentIsNotCaptured() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        defer { monitor.stop(); pasteboard.releaseGlobally() }
        var count = 0
        monitor.onNewRecord = { _ in count += 1 }
        monitor.start()
        let item = NSPasteboardItem()
        item.setString("secret", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([item]))
        monitor.checkForChanges()
        try await Task.sleep(for: .milliseconds(50))
        #expect(count == 0)
    }

    @Test func testStopDiscardsPendingRecordPreparation() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        defer { monitor.stop(); pasteboard.releaseGlobally() }
        var count = 0
        monitor.onNewRecord = { _ in count += 1 }
        monitor.start()
        pasteboard.clearContents()
        #expect(pasteboard.setString("pending", forType: .string))
        monitor.checkForChanges()
        monitor.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(count == 0)
    }

    @Test func testWritingPreservesMultipleItemsAndRichFormats() {
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        defer { pasteboard.releaseGlobally() }
        let payloads = [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("text".utf8)),
            ClipboardPayload(itemIndex: 0, type: "public.html", data: Data("<p>text</p>".utf8)),
            ClipboardPayload(itemIndex: 1, type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/test.txt".utf8))
        ]
        monitor.write(ClipboardRecord(payloads: payloads))
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.pasteboardItems?[0].data(forType: .html) == payloads[1].data)
        #expect(pasteboard.pasteboardItems?[1].data(forType: .fileURL) == payloads[2].data)
    }
}
