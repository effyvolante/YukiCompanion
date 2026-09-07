import AppKit
import SwiftUI

@MainActor
final class SetupGuideWindowController {
    static let shared = SetupGuideWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let setupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            setupWindow.title = "Get Started with Yuki"
            setupWindow.isReleasedWhenClosed = false
            setupWindow.contentView = NSHostingView(rootView: SetupGuideView())
            window = setupWindow
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct SetupGuideView: View {
    @ObservedObject private var settings = CompanionSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Get started").font(.largeTitle.bold()).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.78))
                Text("Follow these steps once to connect Yuki to your app and your normal ChatGPT account in Chrome.").foregroundStyle(.secondary)
                SetupStep(number: 1, title: "Choose your companion settings", detail: "Current app: \(settings.watchedApplication) · Theme: \(settings.themeID)", buttonTitle: "Open Settings") {
                    SettingsWindowController.shared.show()
                }
                SetupStep(number: 2, title: "Allow Screen Recording", detail: "This lets Yuki capture only the selected application window when you ask her to look.", buttonTitle: "Open Screen Recording") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                }
                SetupStep(number: 3, title: "Allow Accessibility", detail: "This enables keyboard-assisted and legacy ChatGPT controls. Chrome extension sync works without it.", buttonTitle: "Open Accessibility") {
                    AppDelegate.openAccessibilitySettings()
                }
                SetupStep(number: 4, title: "Install the Yuki Chrome extension", detail: "Download the repository ZIP using Code → Download ZIP and extract it. Follow ChromeExtension/README.md: type chrome://extensions into Chrome, enable Developer mode, then Load unpacked → ChromeExtension.", buttonTitle: "Get extension from repository") {
                    open("https://github.com/effyvolante/YukiCompanion/tree/main/ChromeExtension")
                }
                SetupStep(number: 5, title: "Bind your App Companion chat", detail: "Open ‘\(settings.chromeConversation)’ in ChatGPT, click the Yuki extension, and choose Bind this tab to Yuki.", buttonTitle: "Open ChatGPT") {
                    open("https://chatgpt.com")
                }
                SetupStep(number: 6, title: "Run a text test", detail: "Open Yuki’s chat window and send: hello yuki", buttonTitle: "Done") {}
                Text("Yuki uses the checked-in Chrome extension as the only ChatGPT DOM integration. No API key or separate ChatGPT login is required.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 620)
        .background(.black.opacity(0.92))
        .foregroundStyle(.white)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.headline).frame(width: 28, height: 28).background(Color.pink).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                Button(buttonTitle, action: action).buttonStyle(.borderedProminent).tint(.pink)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
