import Combine
import Foundation
import Testing
@testable import MePaste

@MainActor
struct AppModelTests {
    @Test func testMoveSelectionSkipsOutsideFilteredRecords() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let first = textRecord("match first")
        let hidden = textRecord("unrelated")
        let last = textRecord("match last")
        [first, hidden, last].forEach(fixture.insert)
        fixture.model.searchText = "match"
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.filteredRecords.map(\.id) == [last.id, first.id])
        #expect(fixture.model.selectedRecordID == last.id)
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.selectedRecordID == first.id)
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.selectedRecordID == first.id)
        fixture.model.moveSelection(by: -1)
        #expect(fixture.model.selectedRecordID == last.id)
    }

    @Test func testNavigationDoesNotRefilterOrPublishUnchangedSelection() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        (0..<100).forEach { fixture.insert(textRecord("match \($0)")) }
        fixture.model.searchText = "match"
        try await waitUntil { !fixture.model.isFiltering }
        var resultUpdates = 0
        var selectionUpdates = 0
        let results = fixture.model.$filteredRecords.dropFirst().sink { _ in resultUpdates += 1 }
        let selection = fixture.model.$selectedRecordID.dropFirst().sink { _ in selectionUpdates += 1 }
        for _ in 0..<20 { fixture.model.moveSelection(by: 1) }
        #expect(resultUpdates == 0)
        #expect(selectionUpdates == 20)
        fixture.model.moveSelection(by: 0)
        #expect(selectionUpdates == 20)
        withExtendedLifetime((results, selection)) {}
    }

    @Test func testRapidQueryChangesDoNotPublishStaleResults() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.insert(textRecord("alpha"))
        let beta = textRecord("beta")
        fixture.insert(beta)
        fixture.model.searchText = "alpha"
        fixture.model.searchText = "missing"
        fixture.model.searchText = "beta"
        #expect(fixture.model.isFiltering)
        #expect(fixture.model.filteredRecords.isEmpty)
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.filteredRecords.map(\.id) == [beta.id])
        #expect(fixture.model.selectedRecordID == beta.id)
    }

    @Test func testReturnCannotCopyStaleResultsWhileSearching() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString("unchanged", forType: .string))
        fixture.insert(textRecord("alpha"))
        fixture.model.searchText = "missing"
        fixture.model.selectCurrentRecord()
        #expect(fixture.pasteboard.string(forType: .string) == "unchanged")
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.selectedRecordID == nil)
    }

    @Test func testClearingQueryCancelsPendingSearch() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.insert(textRecord("alpha"))
        fixture.insert(textRecord("beta"))
        fixture.model.searchText = "missing"
        fixture.model.searchText = " \n "
        #expect(!fixture.model.isSearching)
        #expect(!fixture.model.isFiltering)
        #expect(fixture.model.filteredRecords.count == 2)
        try await Task.sleep(for: .milliseconds(180))
        #expect(fixture.model.filteredRecords.count == 2)
    }

    @Test func testDeletingSelectedSearchResultSelectsRemainingRecord() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let first = textRecord("match first")
        let second = textRecord("match second")
        fixture.insert(first)
        fixture.insert(second)
        fixture.model.searchText = "match"
        try await waitUntil { !fixture.model.isFiltering }
        fixture.model.delete(second)
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.filteredRecords.map(\.id) == [first.id])
        #expect(fixture.model.selectedRecordID == first.id)
    }

    @Test func testClearHistoryCancelsSearchWithoutResurrectingRecords() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        fixture.insert(textRecord("match"))
        fixture.model.searchText = "match"
        fixture.model.clearHistory()
        try await Task.sleep(for: .milliseconds(180))
        #expect(fixture.model.records.isEmpty)
        #expect(fixture.model.filteredRecords.isEmpty)
        #expect(fixture.model.selectedRecordID == nil)
    }

    @Test func testOutOfOrderPreparationKeepsNewestDuplicateAndChronologicalOrder() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let now = Date()
        let newest = textRecord("duplicate", createdAt: now)
        let oldest = textRecord("oldest", createdAt: now.addingTimeInterval(-2))
        fixture.insert(newest)
        fixture.insert(oldest)
        fixture.insert(textRecord("duplicate", createdAt: now.addingTimeInterval(-1)))
        #expect(fixture.model.records.map(\.id) == [newest.id, oldest.id])
        #expect(fixture.model.selectedRecordID == newest.id)
    }

    @Test func testNonmatchingCopyPreservesSelectionWithinSearchResults() async throws {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let first = textRecord("match first")
        fixture.insert(first)
        fixture.insert(textRecord("match second"))
        fixture.model.searchText = "match"
        try await waitUntil { !fixture.model.isFiltering }
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.selectedRecordID == first.id)
        fixture.insert(textRecord("unrelated new copy"))
        try await waitUntil { !fixture.model.isFiltering }
        #expect(fixture.model.selectedRecordID == first.id)
    }

    @Test func testRetentionRebuildsCachedResultsAndRespectsSelection() {
        let fixture = ModelFixture()
        defer { fixture.cleanUp() }
        let now = Date()
        (0..<5).forEach {
            fixture.insert(textRecord("record \($0)", createdAt: now.addingTimeInterval(Double($0))))
        }
        fixture.model.moveSelection(by: 4)
        fixture.model.maximumRecordCount = 2
        #expect(fixture.model.records.count == 2)
        #expect(fixture.model.filteredRecords.map(\.id) == fixture.model.records.map(\.id))
        #expect(fixture.model.selectedRecordID == fixture.model.records.first?.id)
    }
}
