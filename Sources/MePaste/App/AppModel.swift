import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var records: [ClipboardRecord] = []
    @Published private(set) var filteredRecords: [ClipboardRecord] = []
    @Published private(set) var isFiltering = false
    @Published var selectedRecordID: ClipboardRecord.ID?
    @Published var historyScope: HistoryScope = .all {
        didSet {
            guard historyScope != oldValue else { return }
            refreshFilteredRecords()
        }
    }
    @Published var pasteToActiveApplication: Bool {
        didSet {
            defaults.set(pasteToActiveApplication, forKey: Keys.pasteToActiveApplication)
            if !pasteToActiveApplication { directPasteService.cancelPendingPaste() }
        }
    }
    @Published var isCapturePaused: Bool {
        didSet {
            defaults.set(isCapturePaused, forKey: Keys.isCapturePaused)
            clipboardMonitor.isPaused = isCapturePaused
        }
    }
    @Published private(set) var excludedApplications: [ExcludedApplication]
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var actionErrorMessage: String?
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
    private let directPasteService: DirectPasteService
    private weak var panelController: (any HistoryPanelControlling)?
    private weak var hotKeyManager: HotKeyManager?
    private var searchQuery = ClipboardSearchQuery("")
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var saveRevision = 0
    private var persistedRevision = 0

    var isSearching: Bool { !searchQuery.isEmpty }
    var favoriteCount: Int { records.lazy.filter(\.isFavorite).count }
    var ordinaryRecordCount: Int { records.count - favoriteCount }
    var canPasteDirectly: Bool { pasteToActiveApplication && isAccessibilityTrusted }

    init(
        defaults: UserDefaults = .standard,
        historyStore: HistoryStore = HistoryStore(),
        clipboardMonitor: ClipboardMonitor = ClipboardMonitor(),
        directPasteService: DirectPasteService = DirectPasteService()
    ) {
        self.defaults = defaults
        self.historyStore = historyStore
        self.clipboardMonitor = clipboardMonitor
        self.directPasteService = directPasteService
        maximumRecordCount = defaults.object(forKey: Keys.maximumRecordCount) as? Int
            ?? RetentionPolicy.default.maximumRecordCount
        maximumAgeDays = defaults.object(forKey: Keys.maximumAgeDays) as? Int
            ?? RetentionPolicy.default.maximumAgeDays
        hotKey = Self.loadHotKey(from: defaults)
        pasteToActiveApplication = defaults.object(forKey: Keys.pasteToActiveApplication) as? Bool ?? true
        isCapturePaused = defaults.bool(forKey: Keys.isCapturePaused)
        excludedApplications = defaults.data(forKey: Keys.excludedApplications)
            .flatMap { try? JSONDecoder().decode([ExcludedApplication].self, from: $0) } ?? []
        clipboardMonitor.isPaused = isCapturePaused
        clipboardMonitor.excludedApplicationBundleIdentifiers = Set(excludedApplications.map(\.bundleIdentifier))
        isAccessibilityTrusted = directPasteService.isAuthorized

        clipboardMonitor.onNewRecord = { [weak self] record in
            self?.insert(record)
        }
    }

    func attach(hotKeyManager: HotKeyManager) {
        self.hotKeyManager = hotKeyManager
    }

    func attach(panelController: any HistoryPanelControlling) {
        self.panelController = panelController
    }

    func refreshAccessibilityPermission() {
        let trusted = directPasteService.isAuthorized
        if isAccessibilityTrusted != trusted { isAccessibilityTrusted = trusted }
    }

    func requestAccessibilityPermission() {
        directPasteService.requestPermission()
        refreshAccessibilityPermission()
    }

    func excludeApplication(_ application: ExcludedApplication) {
        guard !application.bundleIdentifier.isEmpty,
              !excludedApplications.contains(where: { $0.id == application.id })
        else { return }
        excludedApplications.append(application)
        excludedApplications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveExcludedApplications()
    }

    func removeExcludedApplication(_ application: ExcludedApplication) {
        excludedApplications.removeAll { $0.id == application.id }
        saveExcludedApplications()
    }

    private func saveExcludedApplications() {
        clipboardMonitor.excludedApplicationBundleIdentifiers = Set(excludedApplications.map(\.bundleIdentifier))
        if let data = try? JSONEncoder().encode(excludedApplications) {
            defaults.set(data, forKey: Keys.excludedApplications)
        }
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

    func start(panelController: any HistoryPanelControlling) {
        attach(panelController: panelController)
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
        directPasteService.cancelPendingPaste()
        clipboardMonitor.stop()
        loadTask?.cancel()
        searchTask?.cancel()
        saveTask?.cancel()
    }

    func toggleHistory() {
        directPasteService.cancelPendingPaste()
        actionErrorMessage = nil
        if panelController?.isVisible == true {
            panelController?.dismiss()
        } else {
            setSelection(filteredRecords.first?.id)
            panelController?.show()
        }
    }

    func select(_ record: ClipboardRecord, asPlainText: Bool = false, copyOnly: Bool = false) {
        directPasteService.cancelPendingPaste()
        actionErrorMessage = nil
        guard !isFiltering, let currentRecord = records.first(where: { $0.id == record.id }) else { return }
        guard !asPlainText || currentRecord.plainTextForPasting != nil else {
            actionErrorMessage = "无法将此内容转换为纯文本，剪贴板未更改。"
            return
        }
        guard clipboardMonitor.write(currentRecord, asPlainText: asPlainText) else {
            actionErrorMessage = "无法写入剪贴板，请重试。"
            return
        }

        let expectedChangeCount = clipboardMonitor.changeCount
        refreshAccessibilityPermission()
        let target = panelController?.dismiss()
        guard !copyOnly, canPasteDirectly, let target else { return }
        directPasteService.paste(to: target) { [weak clipboardMonitor] in
            clipboardMonitor?.changeCount == expectedChangeCount
        }
    }

    func toggleFavorite(_ record: ClipboardRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        var updatedRecords = records
        updatedRecords[index].isFavorite.toggle()
        records = retainedRecords(updatedRecords)
        refreshFilteredRecords(preferredSelection: record.id)
        scheduleSave()
    }

    func delete(_ record: ClipboardRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        var updatedRecords = records
        updatedRecords.remove(at: index)
        records = updatedRecords
        refreshFilteredRecords()
        scheduleSave()
    }

    func clearHistory(includeFavorites: Bool = false) {
        let remaining = includeFavorites ? [] : records.filter(\.isFavorite)
        guard remaining.count != records.count else { return }
        records = remaining
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

    func selectCurrentRecord(asPlainText: Bool = false) {
        guard !isFiltering, let selectedRecordID,
              let record = filteredRecords.first(where: { $0.id == selectedRecordID })
        else { return }
        select(record, asPlainText: asPlainText)
    }

    func quickPaste(number: Int, asPlainText: Bool = false) {
        guard !isFiltering, (1...9).contains(number), number <= filteredRecords.count else { return }
        let record = filteredRecords[number - 1]
        setSelection(record.id)
        select(record, asPlainText: asPlainText)
    }

    func hideHistory() {
        directPasteService.cancelPendingPaste()
        panelController?.dismiss()
    }

    private func insert(_ record: ClipboardRecord) {
        var record = record
        var updatedRecords = records
        if let existingIndex = updatedRecords.firstIndex(where: { $0.hasSameContent(as: record) }) {
            // Background preparation may finish after a more recent copy.
            guard updatedRecords[existingIndex].createdAt <= record.createdAt else { return }
            record.isFavorite = record.isFavorite || updatedRecords[existingIndex].isFavorite
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
        let cutoffDate = policy.cutoffDate
        var ordinaryCount = 0
        return records.filter { record in
            if record.isFavorite { return true }
            if let cutoffDate, record.createdAt < cutoffDate { return false }
            if policy.maximumRecordCount > 0, ordinaryCount >= policy.maximumRecordCount { return false }
            ordinaryCount += 1
            return true
        }
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
        let snapshot = historyScope == .favorites ? records.filter(\.isFavorite) : records
        guard !searchQuery.isEmpty, !snapshot.isEmpty else {
            isFiltering = false
            filteredRecords = snapshot
            updateSelection(preferred: selection, fallback: previousSelection)
            return
        }

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
        saveRevision += 1
        let revision = saveRevision
        let snapshot = records
        saveTask = Task { [weak self, historyStore] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await historyStore.save(snapshot)
                if let self { self.persistedRevision = max(self.persistedRevision, revision) }
            } catch is CancellationError {
                // A newer snapshot superseded this save.
            } catch {
                NSLog("Failed to save clipboard history: \(error)")
            }
        }
    }

    /// A quit immediately after favoriting/copying must not lose the debounced save.
    /// Call after stop() on termination; tests can flush their isolated store too.
    func flushPendingHistory() async throws {
        saveTask?.cancel()
        guard persistedRevision != saveRevision else { return }
        let revision = saveRevision
        try await historyStore.save(records)
        persistedRevision = max(persistedRevision, revision)
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
    static let pasteToActiveApplication = "paste.toActiveApplication"
    static let isCapturePaused = "privacy.isCapturePaused"
    static let excludedApplications = "privacy.excludedApplications"
}
