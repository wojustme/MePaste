import Foundation

actor HistorySearch {
    func filter(_ records: [ClipboardRecord], matching query: ClipboardSearchQuery) -> [ClipboardRecord] {
        var matches: [ClipboardRecord] = []
        matches.reserveCapacity(min(records.count, 32))
        for (index, record) in records.enumerated() {
            if index & 31 == 0, Task.isCancelled { return [] }
            if record.matchesSearch(query) {
                matches.append(record)
            }
        }
        return Task.isCancelled ? [] : matches
    }
}
