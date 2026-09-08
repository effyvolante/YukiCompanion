import AppKit
import Foundation

@MainActor
final class UpdateService {
    static let shared = UpdateService()
    static let currentVersion = "1.0.3"
    static let repositoryURL = URL(string: "https://github.com/effyvolante/YukiCompanion")!
    private static let releasesAPI = URL(string: "https://api.github.com/repos/effyvolante/YukiCompanion/releases/latest")!

    private var isChecking = false

    func check(manual: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false }
            do {
                guard let release = try await latestRelease() else {
                    if manual { showNoReleaseAlert() }
                    return
                }
                if isNewer(release.tagName) {
                    showUpdateAlert(for: release)
                } else if manual {
                    showAlert(message: "Yuki is up to date", detail: "You are running Yuki \(Self.currentVersion).", buttons: ["Done"])
                }
            } catch {
                if manual { showAlert(message: "Couldn’t check for updates", detail: "GitHub could not be reached right now. You can check the releases page manually.", buttons: ["Open GitHub", "Later"], openRepositoryOnFirstButton: true) }
            }
        }
    }

    private func latestRelease() async throws -> Release? {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("YukiCompanion/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func isNewer(_ tag: String) -> Bool {
        let current = versionParts(Self.currentVersion)
        let remote = versionParts(tag)
        for index in 0..<max(current.count, remote.count) {
            let lhs = index < current.count ? current[index] : 0
            let rhs = index < remote.count ? remote[index] : 0
            if lhs != rhs { return rhs > lhs }
        }
        return false
    }

    private func versionParts(_ value: String) -> [Int] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    private func showUpdateAlert(for release: Release) {
        let asset = release.assets.first { $0.name.lowercased().contains("macos") && $0.name.lowercased().hasSuffix(".zip") }
        let destination = asset?.browserDownloadURL ?? release.htmlURL
        showAlert(message: "Yuki \(release.tagName) is available", detail: "Download the matching macOS package from GitHub. Quit Yuki before replacing the app, then launch the new copy.", buttons: ["Download update", "Later"], openURL: destination)
    }

    private func showNoReleaseAlert() {
        showAlert(message: "No published update yet", detail: "Yuki checks the project’s GitHub Releases. The latest build will appear there when a release is published.", buttons: ["Open GitHub", "Later"], openRepositoryOnFirstButton: true)
    }

    private func showAlert(message: String, detail: String, buttons: [String], openURL: URL? = nil, openRepositoryOnFirstButton: Bool = false) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        buttons.forEach { alert.addButton(withTitle: $0) }
        if alert.runModal() == .alertFirstButtonReturn {
            if let openURL { NSWorkspace.shared.open(openURL) }
            else if openRepositoryOnFirstButton { NSWorkspace.shared.open(Self.repositoryURL) }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case htmlURL = "html_url"; case assets }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
    }
}
