import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    let hotKey: HotKey
    let onChange: (HotKey) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.hotKey = hotKey
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderView, context: Context) {
        nsView.hotKey = hotKey
        nsView.onChange = onChange
        nsView.needsDisplay = true
    }
}

final class HotKeyRecorderView: NSView {
    var hotKey: HotKey = .default
    var onChange: ((HotKey) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 28)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        guard let hotKey = HotKey(event: event) else {
            NSSound.beep()
            return
        }

        isRecording = false
        onChange?(hotKey)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor)
            .setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "请按下新快捷键…" : hotKey.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
}
