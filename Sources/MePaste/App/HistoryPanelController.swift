import AppKit
import SwiftUI

@MainActor
protocol HistoryPanelControlling: AnyObject {
    var isVisible: Bool { get }
    func show()
    @discardableResult func dismiss() -> pid_t?
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate, HistoryPanelControlling {
    private let panel: HistoryPanel
    private weak var model: AppModel?
    private var localEventMonitor: Any?
    private var previousApp: NSRunningApplication?

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
    }

    func show() {
        guard let model else { return }
        model.refreshAccessibilityPermission()
        // Remember which app was frontmost so we can hand focus back to it
        // after the user picks a record (or dismisses the panel).
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        positionPanel()
        let hostingView = NSHostingView(rootView: HistoryView(model: model))
        // The panel owns its fixed geometry; avoid SwiftUI's intrinsic-size probes.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        // This is a nonactivating panel: take keyboard focus without racing an
        // asynchronous application activation or bringing Settings forward.
        panel.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
    }

    /// Hide the panel and return focus to whichever app was frontmost before
    /// MePaste appeared, so the user lands back where they were.
    @discardableResult
    func dismiss() -> pid_t? {
        let appToRestore = previousApp
        previousApp = nil
        hide()
        guard let appToRestore, !appToRestore.isTerminated,
              appToRestore.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        guard !appToRestore.isActive else { return appToRestore.processIdentifier }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: appToRestore)
            appToRestore.activate()
        } else {
            appToRestore.activate(options: [])
        }
        return appToRestore.processIdentifier
    }

    func hide() {
        previousApp = nil
        panel.orderOut(nil)
        removeKeyboardMonitor()
        panel.makeFirstResponder(nil)
        // Hidden hosting views still observe the model. Release the entire tree,
        // including card tasks and date/animation updates, until the next show.
        panel.contentView = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // The user clicked into another app; let macOS keep focus there.
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
            guard let self, self.panel.isKeyWindow, event.window === self.panel else { return event }
            let isComposing = (self.panel.firstResponder as? NSTextView)?.hasMarkedText() == true
            guard let action = HistoryKeyboardAction.resolve(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isComposing: isComposing
            ) else { return event }

            switch action {
            case .moveSelection(let offset):
                self.model?.moveSelection(by: offset)
            case .useSelection(let asPlainText):
                self.model?.selectCurrentRecord(asPlainText: asPlainText)
            case .quickPaste(let number, let asPlainText):
                self.model?.quickPaste(number: number, asPlainText: asPlainText)
            case .escape:
                if self.model?.isSearching == true {
                    self.model?.searchText = ""
                } else {
                    self.model?.hideHistory()
                }
            }
            return nil
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
