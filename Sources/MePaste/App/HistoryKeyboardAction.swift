import AppKit
import Carbon

/// Keep modifier/IME handling independent of the window so keyboard regressions
/// can be exercised without posting events to the user's applications.
enum HistoryKeyboardAction: Equatable {
    case moveSelection(Int)
    case useSelection(asPlainText: Bool)
    case quickPaste(number: Int, asPlainText: Bool)
    case escape

    static func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isComposing: Bool = false
    ) -> HistoryKeyboardAction? {
        guard !isComposing else { return nil }
        let modifiers = modifiers.intersection([.command, .shift, .control, .option])

        if modifiers == .command || modifiers == [.command, .shift],
           let number = numberedKeys[keyCode] {
            return .quickPaste(number: number, asPlainText: modifiers.contains(.shift))
        }

        switch keyCode {
        case UInt16(kVK_LeftArrow) where modifiers.isEmpty:
            return .moveSelection(-1)
        case UInt16(kVK_RightArrow) where modifiers.isEmpty:
            return .moveSelection(1)
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            guard modifiers.isEmpty || modifiers == .shift else { return nil }
            return .useSelection(asPlainText: modifiers.contains(.shift))
        case UInt16(kVK_Escape) where modifiers.isEmpty:
            return .escape
        default:
            return nil
        }
    }

    private static let numberedKeys: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4, UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8, UInt16(kVK_ANSI_9): 9,
        UInt16(kVK_ANSI_Keypad1): 1, UInt16(kVK_ANSI_Keypad2): 2, UInt16(kVK_ANSI_Keypad3): 3,
        UInt16(kVK_ANSI_Keypad4): 4, UInt16(kVK_ANSI_Keypad5): 5, UInt16(kVK_ANSI_Keypad6): 6,
        UInt16(kVK_ANSI_Keypad7): 7, UInt16(kVK_ANSI_Keypad8): 8, UInt16(kVK_ANSI_Keypad9): 9
    ]
}
