import Foundation

struct RetentionPolicy: Equatable {
    var maximumRecordCount: Int
    var maximumAgeDays: Int

    static let `default` = RetentionPolicy(
        maximumRecordCount: 500,
        maximumAgeDays: 30
    )

    var cutoffDate: Date? {
        guard maximumAgeDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -maximumAgeDays, to: Date())
    }
}
