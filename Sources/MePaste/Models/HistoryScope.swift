enum HistoryScope: String, CaseIterable {
    case all
    case favorites

    var title: String {
        switch self {
        case .all: return "全部历史"
        case .favorites: return "收藏"
        }
    }
}
