import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Capture is demand-driven and window-scoped. It never falls back to a desktop screenshot.
final class WindowScreenshotService {
    struct Capture {
        let png: Data
        let cursor: CursorContext
    }

    private let applicationName: String

    init(applicationName: String) {
        self.applicationName = applicationName
    }

    @MainActor
    func capture() -> Capture? {
        guard let window = WatchedWindowManager(applicationName: applicationName).window(),
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, window.id, [.bestResolution, .boundsIgnoreFraming]),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return Capture(png: png, cursor: CursorContext(global: NSEvent.mouseLocation, window: window.bounds))
    }
}
