import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var records: [ClipboardRecord] = []
    @Published var selectedRecordID: ClipboardRecord.ID?
    @Published var maximumRecordCount: Int {
        didSet {
            UserDefaults.standard.set(maximumRecordCount, forKey: Keys.maximumRecordCount)
            applyRetentionPolicy()
        }
    }
    @Published var maximumAgeDays: Int {
        didSet {
            UserDefaults.standard.set(maximumAgeDays, forKey: Keys.maximumAgeDays)
            applyRetentionPolicy()
        }
    }
    @Published private(set) var hotKey: HotKey
    @Published private(set) var hotKeyErrorMessage: String?

    let clipboardMonitor = ClipboardMonitor()
    let launchAtLoginManager = LaunchAtLoginManager()
    private let historyStore = HistoryStore()
    private weak var panelController: HistoryPanelController?
    private weak var hotKeyManager: HotKeyManager?
    private var saveTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
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
            UserDefaults.standard.set(encoded, forKey: Keys.hotKey)
        }
    }

    func resetHotKey() {
        updateHotKey(.default)
    }

    func start(panelController: HistoryPanelController) {
        self.panelController = panelController
        clipboardMonitor.start()

        Task {
            do {
                records = try await historyStore.load()
                applyRetentionPolicy()
            } catch {
                NSLog("Failed to load clipboard history: \(error)")
            }
        }
    }

    func toggleHistory() {
        if panelController?.isVisible == true {
            panelController?.hide()
        } else {
            selectedRecordID = records.first?.id
            panelController?.show()
        }
    }

    func select(_ record: ClipboardRecord) {
        clipboardMonitor.write(record)
        panelController?.hide()
    }

    func delete(_ record: ClipboardRecord) {
        records.removeAll { $0.id == record.id }
        if selectedRecordID == record.id {
            selectedRecordID = records.first?.id
        }
        scheduleSave()
    }

    func clearHistory() {
        records.removeAll()
        selectedRecordID = nil
        scheduleSave()
    }

    func moveSelection(by offset: Int) {
        guard !records.isEmpty else { return }
        let currentIndex = selectedRecordID
            .flatMap { id in records.firstIndex { $0.id == id } } ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), records.count - 1)
        selectedRecordID = records[targetIndex].id
    }

    func selectCurrentRecord() {
        guard let selectedRecordID,
              let record = records.first(where: { $0.id == selectedRecordID })
        else { return }
        select(record)
    }

    func hideHistory() {
        panelController?.hide()
    }

    private func insert(_ record: ClipboardRecord) {
        if let existingIndex = records.firstIndex(where: { $0.hasSameContent(as: record) }) {
            records.remove(at: existingIndex)
        }
        records.insert(record, at: 0)
        selectedRecordID = record.id
        applyRetentionPolicy()
    }

    private func applyRetentionPolicy() {
        let policy = RetentionPolicy(
            maximumRecordCount: maximumRecordCount,
            maximumAgeDays: maximumAgeDays
        )

        if let cutoffDate = policy.cutoffDate {
            records.removeAll { $0.createdAt < cutoffDate }
        }
        if policy.maximumRecordCount > 0, records.count > policy.maximumRecordCount {
            records = Array(records.prefix(policy.maximumRecordCount))
        }
        if let selectedRecordID,
           !records.contains(where: { $0.id == selectedRecordID }) {
            self.selectedRecordID = records.first?.id
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = records
        saveTask = Task { [historyStore] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                try await historyStore.save(snapshot)
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
