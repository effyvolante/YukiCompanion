import AppKit
import CoreGraphics

struct WoWWindowManager {
    struct Window {
        let id: CGWindowID
        let bounds: CGRect
    }

    private let applicationName: String

    init(applicationName: String = "World of Warcraft") {
        self.applicationName = applicationName
    }

    func window() -> Window? {
        let application: NSRunningApplication?
        if applicationName.caseInsensitiveCompare("World of Warcraft") == .orderedSame {
            // Preserve the known-good WoW lookup as the default path.
            application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.blizzard.worldofwarcraft").first
        } else {
            application = NSWorkspace.shared.runningApplications.first { app in
                app.activationPolicy != .prohibited &&
                app.localizedName?.caseInsensitiveCompare(applicationName) == .orderedSame
            }
        }
        guard let application else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]])?.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == application.processIdentifier }).flatMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let value = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = value["X"], let y = value["Y"],
                  let w = value["Width"], let h = value["Height"] else { return nil }
            return Window(id: id, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }

    func activeWindow() -> CGRect? { window()?.bounds }
}
