import AppKit
import CoreGraphics

struct WatchedWindowManager {
    struct Window {
        let id: CGWindowID
        let bounds: CGRect
    }

    private let applicationName: String

    init(applicationName: String) {
        self.applicationName = applicationName
    }

    func window() -> Window? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: { app in
            app.activationPolicy != .prohibited &&
            app.localizedName?.caseInsensitiveCompare(applicationName) == .orderedSame
        }) else {
            NSLog("[YukiCapture] no running application matched '%@'", applicationName)
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]])?.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == application.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }.compactMap { info -> Window? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let value = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(value["X"]), let y = number(value["Y"]),
                  let w = number(value["Width"]), let h = number(value["Height"]), w > 1, h > 1 else { return nil }
            return Window(id: id, bounds: CGRect(x: x, y: y, width: w, height: h))
        } ?? []
        let selected = windows.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        if selected == nil { NSLog("[YukiCapture] no visible normal window found for '%@'", applicationName) }
        return selected
    }

    func activeWindow() -> CGRect? { window()?.bounds }

    private func number(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let value = value as? CGFloat { return value }
        return nil
    }
}
