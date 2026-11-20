import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MePaste

func textRecord(_ text: String, createdAt: Date = Date()) -> ClipboardRecord {
    ClipboardRecord(createdAt: createdAt, payloads: [
        ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
    ])
}

func imagePayload(width: Int = 1_200, height: Int = 600) throws -> ClipboardPayload {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return ClipboardPayload(itemIndex: 0, type: NSPasteboard.PasteboardType.png.rawValue, data: data as Data)
}

@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), "Timed out waiting for asynchronous work")
}

@MainActor
final class ModelFixture {
    let model: AppModel
    let pasteboard: NSPasteboard
    let directory: URL
    let store: HistoryStore
    private let suiteName = "MePasteTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init(directPasteService: DirectPasteService = DirectPasteService(
        authorizationCheck: { false }, permissionRequest: {}
    )) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = HistoryStore(directoryURL: directory)
        pasteboard = NSPasteboard.withUniqueName()
        defaults = UserDefaults(suiteName: suiteName)!
        model = AppModel(
            defaults: defaults,
            historyStore: store,
            clipboardMonitor: ClipboardMonitor(pasteboard: pasteboard, frontmostApplicationIdentifier: { nil }),
            directPasteService: directPasteService
        )
    }

    func insert(_ record: ClipboardRecord) {
        model.clipboardMonitor.onNewRecord?(record)
    }

    func cleanUp() {
        model.stop()
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class TestHistoryPanel: HistoryPanelControlling {
    var isVisible = true
    var targetProcessIdentifier: pid_t? = 42
    private(set) var dismissCount = 0

    func show() { isVisible = true }

    @discardableResult
    func dismiss() -> pid_t? {
        dismissCount += 1
        isVisible = false
        return targetProcessIdentifier
    }
}

@MainActor
final class DirectPasteFixture {
    var isAuthorized = true
    var frontmostPID: pid_t? = 42
    var releasedModifiers = true
    var clipboardUnchanged = true
    var postedPIDs: [pid_t] = []
    var permissionRequests = 0
    var focusChecks = 0

    lazy var service = DirectPasteService(
        authorizationCheck: { [weak self] in self?.isAuthorized == true },
        permissionRequest: { [weak self] in self?.permissionRequests += 1 },
        frontmostProcessIdentifier: { [weak self] in
            self?.focusChecks += 1
            return self?.frontmostPID
        },
        modifiersReleased: { [weak self] in self?.releasedModifiers == true },
        postPaste: { [weak self] pid in self?.postedPIDs.append(pid) },
        ownProcessIdentifier: 7,
        retryDelay: .milliseconds(2),
        maximumAttempts: 500
    )

    func paste(to pid: pid_t = 42) {
        service.paste(to: pid) { [weak self] in self?.clipboardUnchanged == true }
    }
}
