import CoreGraphics

struct CursorContext: Equatable { let global: CGPoint; let relative: CGPoint; let normalizedX: CGFloat; let normalizedY: CGFloat; let isInside: Bool
    init(global: CGPoint, window: CGRect) { self.global = global; relative = CGPoint(x: global.x - window.minX, y: window.maxY - global.y); normalizedX = window.width > 0 ? (global.x - window.minX) / window.width : 0; normalizedY = window.height > 0 ? (window.maxY - global.y) / window.height : 0; isInside = global.x >= window.minX && global.x <= window.maxX && global.y >= window.minY && global.y <= window.maxY }
}
