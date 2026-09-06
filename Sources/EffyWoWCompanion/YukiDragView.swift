import AppKit
import SwiftUI

@MainActor final class YukiDragView: NSHostingView<PetView> {
    var clicked: (() -> Void)?
    var moved: (() -> Void)?
    var resized: ((CGFloat) -> Void)?
    private var start = NSPoint.zero
    private var origin = NSPoint.zero
    private var dragged = false
    private var resizing = false
    private let resizeHitSize: CGFloat = 18
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false
        resizing = event.locationInWindow.x >= bounds.maxX - resizeHitSize && event.locationInWindow.y <= bounds.minY + resizeHitSize
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        if resizing {
            dragged = true; resized?(max(dx, -dy)); start = point; return
        }
        if hypot(dx, dy) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged && !resizing { clicked?() }
        if dragged { moved?() }
        resizing = false
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: bounds.maxX - resizeHitSize, y: bounds.minY, width: resizeHitSize, height: resizeHitSize), cursor: .crosshair)
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Yuki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
