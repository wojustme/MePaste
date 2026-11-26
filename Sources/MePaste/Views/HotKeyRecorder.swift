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

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }
    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 164, height: 30)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
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

        let insetRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)

        let fillColor: NSColor
        if isRecording {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
        } else if isHovered {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.07)
        } else {
            fillColor = NSColor.controlBackgroundColor
        }
        fillColor.setFill()
        path.fill()

        let strokeColor: NSColor
        if isRecording {
            strokeColor = NSColor.controlAccentColor
        } else if isHovered {
            strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.45)
        } else {
            strokeColor = NSColor.separatorColor
        }
        strokeColor.setStroke()
        path.lineWidth = isRecording ? 1.75 : 1
        path.stroke()

        let text = isRecording ? "请按下组合键…" : hotKey.displayName
        let font = isRecording
            ? NSFont.systemFont(ofSize: 12, weight: .medium)
            : NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
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
