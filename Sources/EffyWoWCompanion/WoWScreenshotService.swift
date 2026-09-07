import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Capture is intentionally demand-driven and window-scoped. This service returns nil
/// rather than falling back to a desktop screenshot when WoW is unavailable.
final class WoWScreenshotService {
    struct Capture {
        let png: Data
        let cursor: CursorContext
    }

    private let applicationName: String

    init(applicationName: String = "World of Warcraft") {
        self.applicationName = applicationName
    }

    @MainActor
    func capture() -> Capture? {
        guard let window = WoWWindowManager(applicationName: applicationName).window(),
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, window.id, [.bestResolution, .boundsIgnoreFraming]),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return Capture(png: png, cursor: CursorContext(global: NSEvent.mouseLocation, window: window.bounds))
    }
}
