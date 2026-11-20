import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var records: [ClipboardRecord] = []
    @Published private(set) var filteredRecords: [ClipboardRecord] = []
    @Published private(set) var isFiltering = false
    @Published var selectedRecordID: ClipboardRecord.ID?
    @Published var searchText = "" {
        didSet {
            let query = ClipboardSearchQuery(searchText)
            guard query != searchQuery else { return }
            searchQuery = query
            refreshFilteredRecords()
        }
    }
    @Published var maximumRecordCount: Int {
        didSet {
            guard maximumRecordCount != oldValue else { return }
            defaults.set(maximumRecordCount, forKey: Keys.maximumRecordCount)
            applyRetentionPolicy()
        }
    }
    @Published var maximumAgeDays: Int {
        didSet {
            guard maximumAgeDays != oldValue else { return }
            defaults.set(maximumAgeDays, forKey: Keys.maximumAgeDays)
            applyRetentionPolicy()
        }
    }
    @Published private(set) var hotKey: HotKey
    @Published private(set) var hotKeyErrorMessage: String?

    let clipboardMonitor: ClipboardMonitor
    let launchAtLoginManager = LaunchAtLoginManager()
    private let defaults: UserDefaults
    private let historyStore: HistoryStore
    private let historySearch = HistorySearch()
    private weak var panelController: HistoryPanelController?
    private weak var hotKeyManager: HotKeyManager?
    private var searchQuery = ClipboardSearchQuery("")
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    var isSearching: Bool { !searchQuery.isEmpty }

    init(
        defaults: UserDefaults = .standard,
        historyStore: HistoryStore = HistoryStore(),
        clipboardMonitor: ClipboardMonitor = ClipboardMonitor()
    ) {
        self.defaults = defaults
        self.historyStore = historyStore
        self.clipboardMonitor = clipboardMonitor
        maximumRecordCount = defaults.object(forKey: Keys.maximumRecordCount) as? Int
            ?? RetentionPolicy.default.maximumRecordCount
        maximumAgeDays = defaults.object(forKey: Keys.maximumAgeDays) as? Int
            ?? RetentionPolicy.default.maximumAgeDays
        hotKey = Self.loadHotKey(from: defaults)

        clipboardMonitor.onNewRecord = { [weak self] record in
            self?.insert(record)
        }
    }

    func attach(hotKeyManager: HotKeyManager) {
        self.hotKeyManager = hotKeyManager
    }

    func updateHotKey(_ newHotKey: HotKey) {
        guard hotKeyManager?.update(newHotKey) == true else {
            hotKeyErrorMessage = "该快捷键已被其他应用占用，请换一个组合。"
            _ = hotKeyManager?.update(hotKey)
            return
        }

        hotKey = newHotKey
        hotKeyErrorMessage = nil
        if let encoded = try? JSONEncoder().encode(newHotKey) {
            defaults.set(encoded, forKey: Keys.hotKey)
        }
    }

    func resetHotKey() {
        updateHotKey(.default)
    }

    func start(panelController: HistoryPanelController) {
        self.panelController = panelController
        guard loadTask == nil else { return }

        loadTask = Task { [weak self, historyStore] in
            do {
                let loadedRecords = try await historyStore.load()
                guard !Task.isCancelled, let self else { return }
                self.records = self.retainedRecords(loadedRecords)
                self.refreshFilteredRecords()
                if self.records.count != loadedRecords.count {
                    self.scheduleSave()
                }
            } catch {
                NSLog("Failed to load clipboard history: \(error)")
            }
            guard !Task.isCancelled else { return }
            // Do not let the asynchronous load overwrite newly captured records.
            self?.clipboardMonitor.start()
        }
    }

    func stop() {
        clipboardMonitor.stop()
        loadTask?.cancel()
        searchTask?.cancel()
        saveTask?.cancel()
    }

    func toggleHistory() {
        if panelController?.isVisible == true {
            panelController?.dismiss()
        } else {
            setSelection(filteredRecords.first?.id)
            panelController?.show()
        }
    }

    func select(_ record: ClipboardRecord) {
        clipboardMonitor.write(record)
        panelController?.dismiss()
    }

    func delete(_ record: ClipboardRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        var updatedRecords = records
        updatedRecords.remove(at: index)
        records = updatedRecords
        refreshFilteredRecords()
        scheduleSave()
    }

    func clearHistory() {
        guard !records.isEmpty else { return }
        records = []
        refreshFilteredRecords()
        scheduleSave()
    }

    func moveSelection(by offset: Int) {
        guard !isFiltering, !filteredRecords.isEmpty else { return }
        let currentIndex = selectedRecordID
            .flatMap { id in filteredRecords.firstIndex { $0.id == id } } ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), filteredRecords.count - 1)
        setSelection(filteredRecords[targetIndex].id)
    }

    func selectCurrentRecord() {
        guard !isFiltering, let selectedRecordID,
              let record = filteredRecords.first(where: { $0.id == selectedRecordID })
        else { return }
        select(record)
    }

    func hideHistory() {
        panelController?.dismiss()
    }

    private func insert(_ record: ClipboardRecord) {
        var updatedRecords = records
        if let existingIndex = updatedRecords.firstIndex(where: { $0.hasSameContent(as: record) }) {
            // Background preparation may finish after a more recent copy.
            guard updatedRecords[existingIndex].createdAt <= record.createdAt else { return }
            updatedRecords.remove(at: existingIndex)
        }
        let insertionIndex = updatedRecords.firstIndex { $0.createdAt < record.createdAt }
            ?? updatedRecords.endIndex
        updatedRecords.insert(record, at: insertionIndex)
        records = retainedRecords(updatedRecords)
        refreshFilteredRecords(preferredSelection: insertionIndex == 0 ? record.id : selectedRecordID)
        scheduleSave()
    }

    private func retainedRecords(_ records: [ClipboardRecord]) -> [ClipboardRecord] {
        let policy = RetentionPolicy(
            maximumRecordCount: maximumRecordCount,
            maximumAgeDays: maximumAgeDays
        )
        var retained = records
        if let cutoffDate = policy.cutoffDate {
            retained.removeAll { $0.createdAt < cutoffDate }
        }
        if policy.maximumRecordCount > 0, retained.count > policy.maximumRecordCount {
            retained = Array(retained.prefix(policy.maximumRecordCount))
        }
        return retained
    }

    private func applyRetentionPolicy() {
        let retained = retainedRecords(records)
        guard retained.count != records.count else { return }
        records = retained
        refreshFilteredRecords()
        scheduleSave()
    }

    private func refreshFilteredRecords(preferredSelection: ClipboardRecord.ID? = nil) {
        searchTask?.cancel()
        let previousSelection = selectedRecordID
        let selection = preferredSelection ?? previousSelection
        guard !searchQuery.isEmpty, !records.isEmpty else {
            isFiltering = false
            filteredRecords = records
            updateSelection(preferred: selection, fallback: previousSelection)
            return
        }

        let snapshot = records
        let query = searchQuery
        // Never allow Return to copy an old result while a new query is in flight.
        isFiltering = true
        filteredRecords = []
        setSelection(nil)
        searchTask = Task { [weak self, historySearch] in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            let matches = await historySearch.filter(snapshot, matching: query)
            guard !Task.isCancelled, let self else { return }
            self.filteredRecords = matches
            self.isFiltering = false
            self.updateSelection(preferred: selection, fallback: previousSelection)
        }
    }

    private func updateSelection(preferred: ClipboardRecord.ID?, fallback: ClipboardRecord.ID?) {
        if let preferred, filteredRecords.contains(where: { $0.id == preferred }) {
            setSelection(preferred)
        } else if let fallback, filteredRecords.contains(where: { $0.id == fallback }) {
            setSelection(fallback)
        } else {
            setSelection(filteredRecords.first?.id)
        }
    }

    private func setSelection(_ id: ClipboardRecord.ID?) {
        guard selectedRecordID != id else { return }
        selectedRecordID = id
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = records
        saveTask = Task { [historyStore] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await historyStore.save(snapshot)
            } catch is CancellationError {
                // A newer snapshot superseded this save.
            } catch {
                NSLog("Failed to save clipboard history: \(error)")
            }
        }
    }

    private static func loadHotKey(from defaults: UserDefaults) -> HotKey {
        guard let data = defaults.data(forKey: Keys.hotKey),
              let hotKey = try? JSONDecoder().decode(HotKey.self, from: data)
        else {
            return .default
        }
        return hotKey
    }
}

private enum Keys {
    static let maximumRecordCount = "retention.maximumRecordCount"
    static let maximumAgeDays = "retention.maximumAgeDays"
    static let hotKey = "shortcut.showHistory"
}
