import AppKit
import SwiftUI

@main
@MainActor
struct MePasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()

    private var panelController: HistoryPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var showHistoryMenuItem: NSMenuItem?
    private var recordCountMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = HistoryPanelController(model: model)
        self.panelController = panelController
        settingsWindowController = SettingsWindowController(model: model)
        model.start(panelController: panelController)

        let hotKeyManager = HotKeyManager(hotKey: model.hotKey)
        hotKeyManager.onPressed = { [weak model] in
            model?.toggleHistory()
        }
        self.hotKeyManager = hotKeyManager
        model.attach(hotKeyManager: hotKeyManager)

        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.invalidate()
        model.clipboardMonitor.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "MePaste"
        )

        let menu = NSMenu()
        menu.delegate = self
        let showItem = NSMenuItem(
            title: "显示剪贴板历史  \(model.hotKey.displayName)",
            action: #selector(showHistory),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        showHistoryMenuItem = showItem

        let recordCountItem = NSMenuItem(
            title: "已保存 \(model.records.count) 条记录",
            action: nil,
            keyEquivalent: ""
        )
        recordCountItem.isEnabled = false
        menu.addItem(recordCountItem)
        recordCountMenuItem = recordCountItem
        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "登录时自动启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem

        let settingsItem = NSMenuItem(
            title: "设置快捷键与历史容量…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MePaste",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.launchAtLoginManager.refresh()
        showHistoryMenuItem?.title = "显示剪贴板历史  \(model.hotKey.displayName)"
        recordCountMenuItem?.title = "已保存 \(model.records.count) 条记录"
        launchAtLoginMenuItem?.state = model.launchAtLoginManager.isEnabled ? .on : .off
    }

    @objc private func showHistory() {
        model.toggleHistory()
    }

    @objc private func showSettings() {
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController?.show()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        model.launchAtLoginManager.setEnabled(!model.launchAtLoginManager.isEnabled)
        launchAtLoginMenuItem?.state = model.launchAtLoginManager.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
