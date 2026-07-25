import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    var onPressed: (() -> Void)?
    private(set) var hotKey: HotKey

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        installHandler()
        register()
    }

    @discardableResult
    func update(_ hotKey: HotKey) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        self.hotKey = hotKey
        return register()
    }

    func invalidate() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    @discardableResult
    private func register() -> Bool {
        let signature = OSType(
            UInt32(ascii: "P") << 24
                | UInt32(ascii: "S") << 16
                | UInt32(ascii: "T") << 8
                | UInt32(ascii: "E")
        )
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }
}

private extension UInt32 {
    init(ascii character: Character) {
        self = character.asciiValue.map(UInt32.init) ?? 0
    }
}
