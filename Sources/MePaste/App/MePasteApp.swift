import AppKit
import Combine
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
    private var pauseCaptureMenuItem: NSMenuItem?
    private var pauseStateSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = HistoryPanelController(model: model)
        self.panelController = panelController
        settingsWindowController = SettingsWindowController(model: model)
        model.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
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
        model.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hotKeyManager?.invalidate()
        model.stop()
        Task {
            do {
                try await model.flushPendingHistory()
            } catch {
                NSLog("Failed to save clipboard history before quitting: \(error)")
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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

        let pauseItem = NSMenuItem(
            title: "暂停记录剪贴板",
            action: #selector(toggleCapturePaused),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)
        pauseCaptureMenuItem = pauseItem

        let launchItem = NSMenuItem(
            title: "登录时自动启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let versionItem = NSMenuItem(
            title: "版本 \(AppVersion.current)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(
            title: "退出 MePaste",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        pauseStateSubscription = model.$isCapturePaused.sink { [weak self] paused in
            self?.statusItem?.button?.image = NSImage(
                systemSymbolName: paused ? "pause.rectangle" : "clipboard",
                accessibilityDescription: paused ? "MePaste（已暂停记录）" : "MePaste"
            )
            self?.statusItem?.button?.toolTip = paused ? "MePaste · 已暂停记录" : "MePaste"
            self?.pauseCaptureMenuItem?.title = paused ? "恢复记录剪贴板" : "暂停记录剪贴板"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.launchAtLoginManager.refresh()
        showHistoryMenuItem?.title = "显示剪贴板历史  \(model.hotKey.displayName)"
        recordCountMenuItem?.title = "已保存 \(model.records.count) 条记录 · \(model.favoriteCount) 条收藏"
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

    @objc private func toggleCapturePaused() {
        model.isCapturePaused.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
