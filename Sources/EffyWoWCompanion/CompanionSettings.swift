import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class CompanionSettings: ObservableObject {
    static let shared = CompanionSettings()
    @Published var companionDisplayName: String { didSet { save() } }
    @Published var themeID: String { didSet { save() } }
    @Published var watchedApplication: String { didSet { save() } }
    @Published var chromeConversation: String { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { save(); applyLaunchAtLogin() } }
    @Published var automaticLook: Bool { didSet { save() } }
    @Published var automaticUpdates: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private enum Key { static let name = "yuki.settings.displayName"; static let theme = "yuki.settings.themeID"; static let watched = "yuki.settings.watchedApplication"; static let conversation = "yuki.settings.chromeConversation"; static let launch = "yuki.settings.launchAtLogin"; static let look = "yuki.settings.automaticLook"; static let updates = "yuki.settings.automaticUpdates" }

    private init() {
        companionDisplayName = defaults.string(forKey: Key.name) ?? "Yuki"
        themeID = defaults.string(forKey: Key.theme) ?? "Yuki"
        watchedApplication = defaults.string(forKey: Key.watched) ?? "World of Warcraft"
        let savedConversation = defaults.string(forKey: Key.conversation)
        chromeConversation = savedConversation == "Yuki — WoW Companion" ? "Yuki — App Companion" : (savedConversation ?? "Yuki — App Companion")
        launchAtLogin = defaults.bool(forKey: Key.launch)
        automaticLook = defaults.bool(forKey: Key.look)
        automaticUpdates = defaults.object(forKey: Key.updates) as? Bool ?? true
    }

    private func save() {
        defaults.set(companionDisplayName, forKey: Key.name); defaults.set(themeID, forKey: Key.theme)
        defaults.set(watchedApplication, forKey: Key.watched); defaults.set(chromeConversation, forKey: Key.conversation)
        defaults.set(launchAtLogin, forKey: Key.launch); defaults.set(automaticLook, forKey: Key.look); defaults.set(automaticUpdates, forKey: Key.updates)
    }

    private func applyLaunchAtLogin() {
        // SMAppService requires a packaged app bundle. Source-run builds keep
        // the preference and simply wait until the distributed app is bundled.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        if launchAtLogin { try? SMAppService.mainApp.register() }
        else { try? SMAppService.mainApp.unregister() }
    }
}

@MainActor
struct CompanionSettingsView: View {
    @ObservedObject var settings: CompanionSettings
    @State private var openApplications: [String] = []

    var body: some View {
        Form {
            Section("Companion") {
                TextField("Name", text: $settings.companionDisplayName)
                Picker("Theme", selection: $settings.themeID) {
                    Text("Yuki").tag("Yuki")
                }
                Text("More themes will appear here when available.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Context") {
                HStack {
                    Picker("Watched application", selection: $settings.watchedApplication) {
                        ForEach(openApplications, id: \.self) { Text($0).tag($0) }
                        if !openApplications.contains(settings.watchedApplication) {
                            Text("\(settings.watchedApplication) (not open)").tag(settings.watchedApplication)
                        }
                    }
                    Button("Refresh", action: refreshApplications).buttonStyle(.borderless)
                }
                TextField("Chrome conversation", text: $settings.chromeConversation)
                Toggle("Look automatically for visual questions", isOn: $settings.automaticLook)
                Text("Look captures only the selected application’s visible window, never the desktop. Screen Recording permission is required.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Startup") { Toggle("Launch Yuki when I sign in", isOn: $settings.launchAtLogin); Toggle("Install updates automatically", isOn: $settings.automaticUpdates) }
            Text("Yuki uses your local Chrome extension and does not use a separate ChatGPT API.").font(.footnote).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 500).padding().onAppear(perform: refreshApplications)
    }

    private func refreshApplications() {
        openApplications = Array(Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let name = app.localizedName, !name.isEmpty else { return nil }
            return name
        })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
