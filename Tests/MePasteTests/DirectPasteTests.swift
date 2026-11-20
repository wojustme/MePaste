import AppKit
import Carbon
import Testing
@testable import MePaste

@MainActor
struct DirectPasteTests {
    @Test func testPasteWaitsForFocusRestorationAndModifierRelease() async throws {
        let fixture = DirectPasteFixture()
        defer { fixture.service.cancelPendingPaste() }
        fixture.frontmostPID = 7
        fixture.releasedModifiers = false
        fixture.paste()
        try await waitUntil { fixture.focusChecks >= 1 }
        #expect(fixture.postedPIDs.isEmpty)
        fixture.frontmostPID = 42
        let checks = fixture.focusChecks
        try await waitUntil { fixture.focusChecks > checks }
        #expect(fixture.postedPIDs.isEmpty)
        fixture.releasedModifiers = true
        try await waitUntil { fixture.postedPIDs.count == 1 }
        #expect(fixture.postedPIDs == [42])
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.postedPIDs.count == 1)
    }

    @Test func testSwitchingToAnUnrelatedAppCancelsPaste() async throws {
        let fixture = DirectPasteFixture()
        defer { fixture.service.cancelPendingPaste() }
        fixture.frontmostPID = 999
        fixture.paste()
        try await waitUntil { fixture.focusChecks == 1 }
        fixture.frontmostPID = 42
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.postedPIDs.isEmpty)
    }

    @Test(arguments: [0, -1, 7])
    func testInvalidOrOwnTargetNeverReceivesPaste(pid: Int32) async throws {
        let fixture = DirectPasteFixture()
        defer { fixture.service.cancelPendingPaste() }
        fixture.frontmostPID = pid
        fixture.paste(to: pid)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.focusChecks == 0)
        #expect(fixture.postedPIDs.isEmpty)
    }

    @Test func testRevokedPermissionOrChangedClipboardCancelsPaste() async throws {
        let fixture = DirectPasteFixture()
        defer { fixture.service.cancelPendingPaste() }
        fixture.paste()
        fixture.isAuthorized = false
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.postedPIDs.isEmpty)
        fixture.isAuthorized = true
        fixture.paste()
        fixture.clipboardUnchanged = false
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.postedPIDs.isEmpty)
    }

    @Test func testNewPasteReplacesPendingPasteAndCancellationStopsIt() async throws {
        let fixture = DirectPasteFixture()
        defer { fixture.service.cancelPendingPaste() }
        fixture.paste(to: 999)
        fixture.paste(to: 42)
        try await waitUntil { fixture.postedPIDs.count == 1 }
        #expect(fixture.postedPIDs == [42])
        fixture.paste()
        fixture.service.cancelPendingPaste()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.postedPIDs == [42])
    }

    @Test func testFocusTimeoutLeavesClipboardWithoutPosting() async throws {
        var checks = 0
        var posted = false
        let service = DirectPasteService(
            authorizationCheck: { true },
            permissionRequest: {},
            frontmostProcessIdentifier: { checks += 1; return 7 },
            modifiersReleased: { true },
            postPaste: { _ in posted = true },
            ownProcessIdentifier: 7,
            retryDelay: .milliseconds(1),
            maximumAttempts: 2
        )
        defer { service.cancelPendingPaste() }
        service.paste(to: 42, whileClipboardUnchanged: { true })
        try await waitUntil { checks == 2 }
        #expect(!posted)
    }
}

struct HistoryKeyboardTests {
    @Test func testReturnAndShiftReturnUseDifferentPasteModes() {
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_Return), modifiers: []) == .useSelection(asPlainText: false))
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_Return), modifiers: .shift) == .useSelection(asPlainText: true))
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifiers: [.shift, .numericPad]) == .useSelection(asPlainText: true))
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_Return), modifiers: .command) == nil)
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_Return), modifiers: .control) == nil)
    }

    @Test func testAllNineCommandShortcutsAndPlainTextVariants() {
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, key) in keys.enumerated() {
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(key), modifiers: .command) == .quickPaste(number: index + 1, asPlainText: false))
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(key), modifiers: [.command, .shift]) == .quickPaste(number: index + 1, asPlainText: true))
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(key), modifiers: []) == nil)
        }
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_ANSI_0), modifiers: .command) == nil)
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_ANSI_1), modifiers: [.command, .option]) == nil)
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_ANSI_Keypad9), modifiers: [.command, .numericPad]) == .quickPaste(number: 9, asPlainText: false))
    }

    @Test func testMarkedTextAlwaysKeepsKeyboardEventsForInputMethod() {
        for key in [kVK_Return, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_ANSI_1] {
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(key), modifiers: [], isComposing: true) == nil)
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(key), modifiers: .command, isComposing: true) == nil)
        }
    }

    @Test func testEditingModifiersAreNotStolenByArrowNavigation() {
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_LeftArrow), modifiers: [.function, .numericPad]) == .moveSelection(-1))
        #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_RightArrow), modifiers: []) == .moveSelection(1))
        for modifiers: NSEvent.ModifierFlags in [.command, .shift, .option, .control] {
            #expect(HistoryKeyboardAction.resolve(keyCode: UInt16(kVK_LeftArrow), modifiers: modifiers) == nil)
        }
    }
}
