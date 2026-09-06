import Foundation
import SwiftUI

@MainActor
final class CompanionSettings: ObservableObject {
    static let shared = CompanionSettings()
    @Published var companionDisplayName: String { didSet { save() } }
    @Published var themeID: String { didSet { save() } }
    @Published var watchedApplication: String { didSet { save() } }
    @Published var chromeConversation: String { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { save() } }
    @Published var automaticLook: Bool { didSet { save() } }
    @Published var automaticUpdates: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private enum Key { static let name = "yuki.settings.displayName"; static let theme = "yuki.settings.themeID"; static let watched = "yuki.settings.watchedApplication"; static let conversation = "yuki.settings.chromeConversation"; static let launch = "yuki.settings.launchAtLogin"; static let look = "yuki.settings.automaticLook"; static let updates = "yuki.settings.automaticUpdates" }

    private init() {
        companionDisplayName = defaults.string(forKey: Key.name) ?? "Yuki"
        themeID = defaults.string(forKey: Key.theme) ?? "Yuki"
        watchedApplication = defaults.string(forKey: Key.watched) ?? "World of Warcraft"
        chromeConversation = defaults.string(forKey: Key.conversation) ?? "Yuki — WoW Companion"
        launchAtLogin = defaults.bool(forKey: Key.launch)
        automaticLook = defaults.bool(forKey: Key.look)
        automaticUpdates = defaults.object(forKey: Key.updates) as? Bool ?? true
    }

    private func save() {
        defaults.set(companionDisplayName, forKey: Key.name); defaults.set(themeID, forKey: Key.theme)
        defaults.set(watchedApplication, forKey: Key.watched); defaults.set(chromeConversation, forKey: Key.conversation)
        defaults.set(launchAtLogin, forKey: Key.launch); defaults.set(automaticLook, forKey: Key.look); defaults.set(automaticUpdates, forKey: Key.updates)
    }
}

@MainActor
struct CompanionSettingsView: View {
    @ObservedObject var settings: CompanionSettings
    var body: some View {
        Form {
            Section("Companion") { TextField("Name", text: $settings.companionDisplayName); TextField("Theme", text: $settings.themeID) }
            Section("Context") {
                TextField("Watched application", text: $settings.watchedApplication)
                TextField("Chrome conversation", text: $settings.chromeConversation)
                Toggle("Look automatically for visual questions", isOn: $settings.automaticLook)
            }
            Section("Startup") { Toggle("Launch Yuki when I sign in", isOn: $settings.launchAtLogin); Toggle("Install updates automatically", isOn: $settings.automaticUpdates) }
            Text("Yuki uses your local Chrome extension and does not use a separate ChatGPT API.").font(.footnote).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 460).padding()
    }
}
