import AppKit
import Foundation
import Testing
@testable import MePaste

@MainActor
struct FavoriteTests {
    @Test func testFavoritesSurviveAgeAndDoNotConsumeOrdinaryCapacity() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.model.maximumRecordCount = 1
        fixture.model.maximumAgeDays = 1
        var favorite = textRecord("permanent", createdAt: Date().addingTimeInterval(-86400 * 365))
        favorite.isFavorite = true
        fixture.insert(favorite)
        fixture.insert(textRecord("older ordinary"))
        let latest = textRecord("latest")
        fixture.insert(latest)
        #expect(fixture.model.records.map(\.id) == [latest.id, favorite.id])
        #expect(fixture.model.favoriteCount == 1)
        #expect(fixture.model.ordinaryRecordCount == 1)
    }

    @Test func testUnfavoritingImmediatelyAppliesRetention() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        var favorite = textRecord("expired", createdAt: Date().addingTimeInterval(-86400 * 365))
        favorite.isFavorite = true
        fixture.insert(favorite)
        fixture.model.toggleFavorite(favorite)
        #expect(fixture.model.records.isEmpty)
        #expect(fixture.model.selectedRecordID == nil)
    }

    @Test func testRecopyingFavoritePreservesFavoriteWithoutDuplicates() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let original = textRecord("snippet", createdAt: Date().addingTimeInterval(-10))
        fixture.insert(original)
        fixture.model.toggleFavorite(original)
        let newCopy = textRecord("snippet")
        fixture.insert(newCopy)
        #expect(fixture.model.records.count == 1)
        #expect(fixture.model.records.first?.createdAt == newCopy.createdAt)
        #expect(fixture.model.records.first?.isFavorite == true)
        fixture.insert(original)
        #expect(fixture.model.favoriteCount == 1)
    }

    @Test func testFavoritesScopeAndSearchComposeAndCancelStaleResults() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let favorite = textRecord("needle favorite")
        fixture.insert(favorite)
        fixture.model.toggleFavorite(favorite)
        fixture.insert(textRecord("needle ordinary"))
        fixture.model.searchText = "needle"
        fixture.model.historyScope = .favorites
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.filteredRecords.map(\.id) == [favorite.id])
        fixture.model.toggleFavorite(favorite)
        #expect(fixture.model.filteredRecords.isEmpty)
        #expect(fixture.model.selectedRecordID == nil)
        fixture.model.historyScope = .all
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.filteredRecords.count == 2)
    }

    @Test func testClearingHistoryPreservesFavoritesUnlessExplicitlyRequested() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let favorite = textRecord("keep favorite")
        fixture.insert(favorite)
        fixture.model.toggleFavorite(favorite)
        fixture.insert(textRecord("ordinary"))
        fixture.model.searchText = "keep"
        fixture.model.clearHistory()
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.records.map(\.id) == [favorite.id])
        #expect(fixture.model.filteredRecords.map(\.id) == [favorite.id])
        fixture.model.clearHistory(includeFavorites: true)
        #expect(fixture.model.records.isEmpty)
        #expect(fixture.model.filteredRecords.isEmpty)
    }

    @Test func testFavoriteIsFlushedOnImmediateStopAndRestoredOnLoad() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let original = textRecord("persist favorite")
        fixture.insert(original)
        fixture.model.toggleFavorite(original)
        fixture.model.stop()
        try await fixture.model.flushPendingHistory()
        let saved = try await fixture.store.load()
        #expect(saved.count == 1)
        #expect(saved.first?.isFavorite == true)
        let reloaded = AppModel(
            defaults: fixture.defaults,
            historyStore: fixture.store,
            clipboardMonitor: ClipboardMonitor(pasteboard: fixture.pasteboard, frontmostApplicationIdentifier: { nil }),
            directPasteService: DirectPasteService(authorizationCheck: { false }, permissionRequest: {})
        )
        defer { reloaded.stop() }
        let panel = TestHistoryPanel()
        reloaded.start(panelController: panel)
        try await waitUntil { reloaded.favoriteCount == 1 }
        #expect(reloaded.records.first?.id == original.id)
    }

    @Test func testFlushWithoutChangesDoesNotCreateOrOverwriteHistory() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let existing = [textRecord("on disk, not loaded yet")]
        try await fixture.store.save(existing)
        fixture.model.stop()
        try await fixture.model.flushPendingHistory()
        #expect(try await fixture.store.load() == existing)
    }
}

@MainActor
struct EverydayPasteTests {
    @Test func testPermissionDeniedFallsBackToCopyWithoutPrompting() async throws {
        let direct = DirectPasteFixture()
        direct.isAuthorized = false
        let fixture = ModelFixture(directPasteService: direct.service)
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)
        let record = textRecord("safe fallback")
        fixture.insert(record)
        fixture.model.select(record)
        #expect(fixture.pasteboard.string(forType: .string) == "safe fallback")
        #expect(panel.dismissCount == 1)
        #expect(!fixture.model.canPasteDirectly)
        try await Task.sleep(for: .milliseconds(30))
        #expect(direct.postedPIDs.isEmpty)
        #expect(direct.permissionRequests == 0)
        fixture.model.requestAccessibilityPermission()
        #expect(direct.permissionRequests == 1)
    }

    @Test func testAuthorizedSelectionPastesOnlyIntoRestoredApplication() async throws {
        let direct = DirectPasteFixture()
        let fixture = ModelFixture(directPasteService: direct.service)
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)
        fixture.insert(textRecord("paste me"))
        fixture.model.selectCurrentRecord()
        try await waitUntil { !direct.postedPIDs.isEmpty }
        #expect(direct.postedPIDs == [panel.targetProcessIdentifier])
        #expect(fixture.pasteboard.string(forType: .string) == "paste me")
        #expect(panel.dismissCount == 1)
    }

    @Test func testExplicitCopyAndDisabledDirectPasteNeverPostKeys() async throws {
        let direct = DirectPasteFixture()
        let fixture = ModelFixture(directPasteService: direct.service)
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)
        let record = textRecord("copy only")
        fixture.insert(record)
        fixture.model.select(record, copyOnly: true)
        fixture.model.pasteToActiveApplication = false
        fixture.model.select(record)
        try await Task.sleep(for: .milliseconds(30))
        #expect(direct.postedPIDs.isEmpty)
        #expect(fixture.pasteboard.string(forType: .string) == "copy only")
    }

    @Test func testChangingClipboardOrReopeningPanelCancelsScheduledPaste() async throws {
        let direct = DirectPasteFixture()
        let fixture = ModelFixture(directPasteService: direct.service)
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)
        let record = textRecord("old clipboard")
        fixture.insert(record)
        fixture.model.select(record)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("new clipboard", forType: .string)
        try await Task.sleep(for: .milliseconds(30))
        #expect(direct.postedPIDs.isEmpty)
        fixture.model.select(record)
        fixture.model.toggleHistory()
        try await Task.sleep(for: .milliseconds(30))
        #expect(direct.postedPIDs.isEmpty)
        #expect(panel.isVisible)
    }

    @Test func testNumberedPasteUsesCurrentFilteredFavoriteList() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let first = textRecord("match first")
        let second = textRecord("match second")
        for record in [first, second] {
            fixture.insert(record)
            fixture.model.toggleFavorite(record)
        }
        fixture.insert(textRecord("match ordinary"))
        fixture.model.historyScope = .favorites
        fixture.model.searchText = "match"
        try await waitUntil { !fixture.model.isFiltering }
        fixture.model.quickPaste(number: 2)
        #expect(fixture.pasteboard.string(forType: .string) == "match first")
        #expect(fixture.model.selectedRecordID == first.id)
    }

    @Test func testNumberedPasteIgnoresInvalidNumbersAndInFlightSearch() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.insert(textRecord("record"))
        fixture.pasteboard.setString("unchanged", forType: .string)
        for number in [0, -1, 2, 9, 10] { fixture.model.quickPaste(number: number) }
        #expect(fixture.pasteboard.string(forType: .string) == "unchanged")
        fixture.model.searchText = "missing"
        fixture.model.quickPaste(number: 1)
        fixture.model.selectCurrentRecord(asPlainText: true)
        #expect(fixture.pasteboard.string(forType: .string) == "unchanged")
        try await waitUntil { !fixture.model.isFiltering }
        fixture.model.quickPaste(number: 1)
        #expect(fixture.pasteboard.string(forType: .string) == "unchanged")
    }

    @Test func testPlainTextSelectionStripsFormattingAndKeepsStoredOriginal() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let record = ClipboardRecord(payloads: [
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("hello".utf8)),
            ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>hello</b>".utf8))
        ])
        fixture.insert(record)
        fixture.model.quickPaste(number: 1, asPlainText: true)
        #expect(fixture.pasteboard.string(forType: .string) == "hello")
        #expect(fixture.pasteboard.data(forType: .html) == nil)
        #expect(fixture.model.records.first?.payloads == record.payloads)
        fixture.model.selectCurrentRecord()
        #expect(fixture.pasteboard.data(forType: .html) == record.payload(for: .html))
    }

    @Test func testUnsupportedPlainTextKeepsClipboardAndPanelOpen() throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)
        fixture.insert(ClipboardRecord(payloads: [try imagePayload()]))
        fixture.pasteboard.setString("do not erase", forType: .string)
        fixture.model.selectCurrentRecord(asPlainText: true)
        #expect(fixture.pasteboard.string(forType: .string) == "do not erase")
        #expect(panel.dismissCount == 0)
        #expect(fixture.model.actionErrorMessage != nil)
    }

    @Test func testDeletedRecordCannotBeUsedFromStaleCard() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let record = textRecord("deleted")
        fixture.insert(record)
        fixture.model.delete(record)
        fixture.pasteboard.setString("unchanged", forType: .string)
        fixture.model.select(record)
        #expect(fixture.pasteboard.string(forType: .string) == "unchanged")
    }

    @Test func testSelectingOlderRecordPromotesItToFrontOnReopenAndPersistsOrder() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let panel = TestHistoryPanel()
        fixture.model.attach(panelController: panel)

        let now = Date()
        let oldest = textRecord("oldest item", createdAt: now.addingTimeInterval(-30))
        let middle = textRecord("middle item", createdAt: now.addingTimeInterval(-20))
        let newest = textRecord("newest item", createdAt: now.addingTimeInterval(-10))
        [oldest, middle, newest].forEach(fixture.insert)

        #expect(fixture.model.records.map(\.id) == [newest.id, middle.id, oldest.id])

        // Select and copy the oldest history item.
        fixture.model.select(oldest, copyOnly: true)
        #expect(fixture.pasteboard.string(forType: .string) == "oldest item")
        #expect(fixture.model.records.map(\.id) == [oldest.id, newest.id, middle.id])
        #expect(fixture.model.filteredRecords.map(\.id) == [oldest.id, newest.id, middle.id])
        #expect(fixture.model.quickPasteNumber(for: oldest.id) == 1)

        // Reopening the history panel immediately focuses the previously selected record.
        fixture.model.toggleHistory()
        #expect(panel.isVisible)
        #expect(fixture.model.selectedRecordID == oldest.id)
        #expect(fixture.model.filteredRecords.first?.id == oldest.id)

        // Order is persisted across relaunch.
        fixture.model.stop()
        try await fixture.model.flushPendingHistory()
        let saved = try await fixture.store.load()
        #expect(saved.map(\.id) == [oldest.id, newest.id, middle.id])
    }
}
