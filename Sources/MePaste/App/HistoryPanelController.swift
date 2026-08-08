import AppKit
import Carbon
import SwiftUI

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
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
        panel.contentView = NSHostingView(rootView: HistoryView(model: model))
    }

    func show() {
        // Remember which app was frontmost so we can hand focus back to it
        // after the user picks a record (or dismisses the panel).
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
    }

    /// Hide the panel and return focus to whichever app was frontmost before
    /// MePaste appeared, so the user lands back where they were.
    func dismiss() {
        let appToRestore = previousApp
        previousApp = nil
        hide()
        guard let appToRestore else { return }
        if #available(macOS 14.0, *) {
            appToRestore.activate()
        } else {
            appToRestore.activate(options: [])
        }
    }

    func hide() {
        previousApp = nil
        panel.orderOut(nil)
        removeKeyboardMonitor()
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
            guard let self else { return event }

            if let textView = self.panel.firstResponder as? NSTextView {
                if textView.hasMarkedText() {
                    return event
                }

                switch event.keyCode {
                case KeyCode.leftArrow where event.hasOnlyNavigationModifiers:
                    self.model?.moveSelection(by: -1)
                    return nil
                case KeyCode.rightArrow where event.hasOnlyNavigationModifiers:
                    self.model?.moveSelection(by: 1)
                    return nil
                case KeyCode.returnKey:
                    self.model?.selectCurrentRecord()
                    return nil
                case KeyCode.escape:
                    if self.model?.isSearching == true {
                        self.model?.searchText = ""
                    } else {
                        self.dismiss()
                    }
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case KeyCode.leftArrow:
                self.model?.moveSelection(by: -1)
                return nil
            case KeyCode.rightArrow:
                self.model?.moveSelection(by: 1)
                return nil
            case KeyCode.returnKey:
                self.model?.selectCurrentRecord()
                return nil
            case KeyCode.escape:
                self.dismiss()
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

private enum KeyCode {
    static let leftArrow = UInt16(kVK_LeftArrow)
    static let rightArrow = UInt16(kVK_RightArrow)
    static let returnKey = UInt16(kVK_Return)
    static let escape = UInt16(kVK_Escape)
}

private extension NSEvent {
    var hasOnlyNavigationModifiers: Bool {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
            .isEmpty
    }
}
