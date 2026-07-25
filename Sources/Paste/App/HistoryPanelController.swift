import AppKit
import SwiftUI

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let panel: HistoryPanel
    private weak var model: AppModel?
    private var localEventMonitor: Any?

    var isVisible: Bool {
        panel.isVisible
    }

    init(model: AppModel) {
        self.model = model
        panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 340),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HistoryView(model: model))
    }

    func show() {
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyboardMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screenFrame = screen?.frame else { return }

        let height: CGFloat = 340
        panel.setFrame(
            NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: height
            ),
            display: true
        )
    }

    private func installKeyboardMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            switch event.keyCode {
            case 123:
                self.model?.moveSelection(by: -1)
                return nil
            case 124:
                self.model?.moveSelection(by: 1)
                return nil
            case 36:
                self.model?.selectCurrentRecord()
                return nil
            case 53:
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}
