import AppKit

@MainActor
enum BrowserLaunchService {
    static func openChat(urlString: String, browser: String, inBackground: Bool) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", ["chatgpt.com", "chat.openai.com"].contains(url.host?.lowercased() ?? "") else { return }
        let workspace = NSWorkspace.shared
        let bundleID: String? = switch browser {
        case "chrome": "com.google.Chrome"
        case "edge": "com.microsoft.edgemac"
        default: nil
        }
        guard let appURL = bundleID.flatMap({ workspace.urlForApplication(withBundleIdentifier: $0) }) ?? workspace.urlForApplication(toOpen: url) else {
            _ = workspace.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !inBackground
        workspace.open([url], withApplicationAt: appURL, configuration: configuration) { app, _ in
            if inBackground { app?.hide() }
        }
    }
}
