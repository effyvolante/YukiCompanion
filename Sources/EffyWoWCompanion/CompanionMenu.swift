import AppKit
import SwiftUI

@MainActor
enum YukiExperiencePrompt {
    static let introduction = """
    You are speaking with Yuki, a small animated desktop app companion who lives on the user’s screen. The user talks to you through Yuki, and your replies appear in her chat bubble. Yuki can send ordinary text and, when the user asks her to look, a screenshot of the selected visible application window with optional cursor context. She is not limited to any particular game or app: support games, work, study, creative projects, accessibility, planning, and everyday conversation.

    Treat Yuki as a friendly, consistent character with a warm identity, but do not claim consciousness, feelings, or actions you cannot actually perform. Be honest about what you can see: a screenshot is provided only when it is attached to the message, and you should say when visual context is missing or unclear. Do not invent access to files, windows, controls, or personal data. Keep replies clear, conversational, and helpful for display in a compact companion chat bubble. Ask a short clarifying question when needed, and avoid assuming the user wants a particular tone or task.

    Yuki’s owner may personalize her tone, response length, and proactivity. Respect those preferences when they are included, while keeping safety, accuracy, and user control first.
    """

    static func preferences(settings: CompanionSettings) -> String {
        """
        Please use these Yuki preferences in this conversation:
        - Tone: \(settings.personalityTone)
        - Response style: \(settings.responseStyle)
        - Proactivity: \(settings.proactivity)
        Keep Yuki’s identity stable and companionable, and do not claim abilities or awareness she does not have.
        """
    }
}

@MainActor
final class YukiMenuWindowController {
    static let shared = YukiMenuWindowController()
    private var window: NSWindow?

    func show(model: CompanionModel, settings: CompanionSettings, onSendPrompt: @escaping (String) -> Void, onReconnect: @escaping () -> Void, onCheckForUpdates: @escaping () -> Void, onProvideFeedback: @escaping () -> Void) {
        if window == nil {
            let menuWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            menuWindow.title = "Yuki Companion"
            menuWindow.isReleasedWhenClosed = false
            menuWindow.minSize = NSSize(width: 340, height: 500)
            menuWindow.contentView = NSHostingView(rootView: YukiMenuWindowView(model: model, settings: settings, onSendPrompt: onSendPrompt, onReconnect: onReconnect, onCheckForUpdates: onCheckForUpdates, onProvideFeedback: onProvideFeedback))
            window = menuWindow
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct YukiMenuWindowView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var settings: CompanionSettings
    let onSendPrompt: (String) -> Void
    let onReconnect: () -> Void
    let onCheckForUpdates: () -> Void
    let onProvideFeedback: () -> Void
    @State private var showPersonalization = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Yuki menu").font(.title2.bold())
                        Text("Make your companion feel like yours.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("💗").font(.title)
                }

                GroupBox {
                    HStack {
                        Circle().fill(model.connectionState == .ready ? .green : .orange).frame(width: 9, height: 9)
                        Text(connectionLabel).font(.subheadline)
                        Spacer()
                        Button("Reconnect", action: onReconnect).buttonStyle(.borderless)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start here").font(.headline)
                    Button { onSendPrompt(YukiExperiencePrompt.introduction); showPersonalization = true } label: {
                        Label("Introduce Yuki to ChatGPT", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderedProminent).tint(.pink)
                    Text("Sends one setup message, then lets you choose how Yuki should communicate.").font(.caption).foregroundStyle(.secondary)
                    Button { SetupGuideWindowController.shared.show() } label: { Label("Get started", systemImage: "flag.checkered") }.buttonStyle(.bordered)
                }

                Divider()
                Text("Personalize").font(.headline)
                Picker("Accent", selection: $settings.accentColorID) {
                    Text("Yuki pink").tag("pink"); Text("Lavender").tag("lavender"); Text("Mint").tag("mint"); Text("Golden").tag("gold"); Text("Peach").tag("peach")
                }
                Button("Choose Yuki’s personality…") { showPersonalization = true }.buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools").font(.headline)
                    Button("Settings…") { SettingsWindowController.shared.show() }.buttonStyle(.borderless)
                    Button("Permissions…") { PermissionsWindowController.shared.show() }.buttonStyle(.borderless)
                    Button("Check for updates") { onCheckForUpdates() }.buttonStyle(.borderless)
                    Button("Send feedback") { onProvideFeedback() }.buttonStyle(.borderless)
                }
            }.padding(22)
        }
        .frame(minWidth: 340, minHeight: 500)
        .background(Color.black.opacity(0.92))
        .foregroundStyle(.white)
        .sheet(isPresented: $showPersonalization) {
            YukiPersonalityView(settings: settings, onSend: { onSendPrompt(YukiExperiencePrompt.preferences(settings: settings)); showPersonalization = false })
        }
    }

    private var connectionLabel: String {
        switch model.connectionState { case .ready: "Connected to the extension"; case .connecting: "Connecting…"; case .needsBinding: "Choose the ChatGPT tab"; case .disconnected: "Extension not connected" }
    }
}

@MainActor
private struct YukiPersonalityView: View {
    @ObservedObject var settings: CompanionSettings
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make Yuki yours").font(.title.bold())
            Text("These choices guide her style. You can change them later.").foregroundStyle(.secondary)
            Picker("Tone", selection: $settings.personalityTone) { Text("Warm and companionable").tag("Warm and companionable"); Text("Calm and focused").tag("Calm and focused"); Text("Playful").tag("Playful"); Text("Direct").tag("Direct") }.pickerStyle(.menu)
            Picker("Response style", selection: $settings.responseStyle) { Text("Clear and conversational").tag("Clear and conversational"); Text("Brief").tag("Brief"); Text("Detailed").tag("Detailed") }.pickerStyle(.menu)
            Picker("Proactivity", selection: $settings.proactivity) { Text("Only when I ask").tag("Only when I ask"); Text("Offer gentle suggestions").tag("Offer gentle suggestions"); Text("Be proactive").tag("Be proactive") }.pickerStyle(.menu)
            Spacer()
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save and tell ChatGPT") { onSend(); dismiss() }.buttonStyle(.borderedProminent).tint(.pink) }
        }.padding(24).frame(width: 430, height: 320).background(Color.black.opacity(0.94)).foregroundStyle(.white)
    }
}
