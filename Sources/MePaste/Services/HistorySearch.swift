import Foundation

actor HistorySearch {
    func filter(_ records: [ClipboardRecord], matching query: ClipboardSearchQuery) -> [ClipboardRecord] {
        var matches: [ClipboardRecord] = []
        for record in records {
            guard !Task.isCancelled else { return [] }
            if record.matchesSearch(query) {
                matches.append(record)
            }
        }
        return matches
    }
}
