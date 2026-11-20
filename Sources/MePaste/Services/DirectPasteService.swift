import AppKit
@preconcurrency import ApplicationServices
import Carbon

/// Sends only an explicit, user-selected paste, never arbitrary keystrokes.
/// Dependencies are injectable so tests don't need Accessibility access or touch
/// another application's input fields.
@MainActor
final class DirectPasteService {
    private let authorizationCheck: () -> Bool
    private let permissionRequest: () -> Void
    private let frontmostProcessIdentifier: () -> pid_t?
    private let modifiersReleased: () -> Bool
    private let postPaste: (pid_t) -> Void
    private let ownProcessIdentifier: pid_t
    private let retryDelay: Duration
    private let maximumAttempts: Int
    private var pasteTask: Task<Void, Never>?

    var isAuthorized: Bool { authorizationCheck() }

    init(
        authorizationCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        permissionRequest: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        },
        frontmostProcessIdentifier: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        modifiersReleased: @escaping () -> Bool = {
            CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
                .isEmpty
        },
        postPaste: @escaping (pid_t) -> Void = { postPasteShortcut(to: $0) },
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        retryDelay: Duration = .milliseconds(25),
        maximumAttempts: Int = 40
    ) {
        self.authorizationCheck = authorizationCheck
        self.permissionRequest = permissionRequest
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.modifiersReleased = modifiersReleased
        self.postPaste = postPaste
        self.ownProcessIdentifier = ownProcessIdentifier
        self.retryDelay = retryDelay
        self.maximumAttempts = maximumAttempts
    }

    func requestPermission() {
        // Only called from an explicit settings action, never on launch/paste.
        permissionRequest()
    }

    func cancelPendingPaste() {
        pasteTask?.cancel()
        pasteTask = nil
    }

    func paste(to processIdentifier: pid_t, whileClipboardUnchanged: @escaping () -> Bool) {
        cancelPendingPaste()
        guard isAuthorized, processIdentifier > 0,
              processIdentifier != ownProcessIdentifier
        else { return }

        pasteTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<maximumAttempts {
                do {
                    try await Task.sleep(for: retryDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled, isAuthorized, whileClipboardUnchanged() else { return }
                let frontmost = frontmostProcessIdentifier()
                // Focus restoration is asynchronous. If the user switches to a
                // different app while waiting, don't send the clipboard there.
                guard frontmost == processIdentifier || frontmost == ownProcessIdentifier
                        || frontmost == nil
                else { return }
                guard frontmost == processIdentifier, modifiersReleased() else { continue }
                postPaste(processIdentifier)
                return
            }
            // Activation failed/timed out: the selected content is still copied.
        }
    }

    private static func postPasteShortcut(to processIdentifier: pid_t) {
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // Target the captured application as a second safeguard against a focus
        // race between the last check and delivery of the shortcut.
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }
}
