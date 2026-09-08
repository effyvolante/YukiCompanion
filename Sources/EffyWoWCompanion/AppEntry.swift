import AppKit
import ApplicationServices
import SwiftUI

@main @MainActor
struct EffyWoWCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { CompanionSettingsView(settings: CompanionSettings.shared) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",", modifiers: [.command])
                }
            }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            settingsWindow.title = "Yuki Companion Settings"
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.contentView = NSHostingView(rootView: CompanionSettingsView(settings: CompanionSettings.shared))
            window = settingsWindow
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ChromeBridge.shared.start()
        overlay = OverlayController(settings: CompanionSettings.shared)
        overlay.show()
        showFirstRunGuidanceIfNeeded()
        showPermissionGuidanceIfNeeded()
        if CompanionSettings.shared.automaticUpdates { UpdateService.shared.check() }
    }

    private func showFirstRunGuidanceIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "yuki.onboarding.seen") else { return }
        let alert = NSAlert()
        alert.messageText = "Welcome to Yuki Companion"
        alert.informativeText = "Yuki will guide you through Accessibility and Screen Recording approval, then help you connect the Chrome extension. Yuki captures only the selected application’s visible window."
        alert.addButton(withTitle: "Open Yuki Permissions")
        alert.addButton(withTitle: "I’ll do this later")
        if alert.runModal() == .alertFirstButtonReturn { PermissionsWindowController.shared.show() }
        UserDefaults.standard.set(true, forKey: "yuki.onboarding.seen")
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openAccessibilitySettings() }
    }

    static func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if !CGPreflightScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showPermissionGuidanceIfNeeded() {
        guard !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            PermissionsWindowController.shared.show()
        }
    }
}

@MainActor final class YukiChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class OverlayController {
    private let settings: CompanionSettings
    private let petPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let chatPanel = YukiChatPanel(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    private let model = CompanionModel()
    private var petSize: CGFloat = 64

    init(settings: CompanionSettings) { self.settings = settings }

    func show() {
        let savedSize = CGFloat(UserDefaults.standard.double(forKey: "yuki.petSize"))
        if savedSize > 0 { petSize = savedSize.clamped(to: 48...128) }
        configure(petPanel); configure(chatPanel)
        chatPanel.minSize = NSSize(width: 300, height: 260)
        chatPanel.maxSize = NSSize(width: 720, height: 800)
        chatPanel.hasShadow = true
        chatPanel.isReleasedWhenClosed = false

        let dragView = YukiDragView(rootView: PetView(model: model, settings: settings))
        dragView.clicked = { [weak self] in self?.toggleBubble() }
        dragView.moved = { [weak self] in self?.savePetFrame(); self?.repositionBubble() }
        dragView.resized = { [weak self] delta in self?.resizePet(by: delta) }
        petPanel.contentView = dragView
        chatPanel.contentView = NSHostingView(rootView: YukiChatView(model: model, settings: settings, companionName: settings.companionDisplayName, onSend: { [weak self] in self?.send() }, onCheckWorkChat: { [weak self] in self?.checkWorkChat() }, onCheckForUpdates: { UpdateService.shared.check(manual: true) }, onProvideFeedback: { FeedbackService.openForm() }, onClose: { [weak self] in self?.toggleBubble() }))

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = UserDefaults.standard.string(forKey: "yuki.petFrame").map(NSRectFromString)
        let frame = saved ?? NSRect(x: screen.maxX - 110, y: screen.midY, width: petSize, height: petSize)
        petPanel.setFrame(frame.fitted(to: screen, size: NSSize(width: petSize, height: petSize)), display: true)
        petPanel.orderFrontRegardless()
    }

    private func configure(_ panel: NSPanel) {
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = false; panel.sharingType = .readOnly
    }

    private func toggleBubble() {
        model.state = .clicked
        if chatPanel.isVisible {
            chatPanel.orderOut(nil); model.state = .idle
        } else {
            repositionBubble(); chatPanel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); model.focusComposer += 1
            Task { @MainActor [weak model] in
                try? await Task.sleep(for: .milliseconds(650))
                if model?.state == .clicked { model?.state = .idle }
            }
        }
    }

    private func repositionBubble() {
        guard let screen = petPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        var size = chatPanel.frame.size
        if size.width < 1 { size = NSSize(width: 380, height: 430) }
        let opensLeft = petPanel.frame.midX > screen.midX
        var origin = NSPoint(x: opensLeft ? petPanel.frame.minX - size.width - 10 : petPanel.frame.maxX + 10, y: petPanel.frame.midY - size.height * 0.72)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        chatPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func send() {
        guard let text = model.takeDraft() else { return }
        let includeAppWindow = model.includeAppWindow || (settings.automaticLook && DeicticQuestionDetector.needsContext(text))
        model.includeAppWindow = false
        model.append(.user, text); model.state = .waiting
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var outbound = text
                var imageData: Data?
                if includeAppWindow {
                    model.state = .capturing
                    guard CGPreflightScreenCaptureAccess() else {
                        model.append(.yuki, "Allow Yuki in System Settings → Privacy & Security → Screen Recording, then restart Yuki and try the eye button again.")
                        model.state = .error
                        return
                    }
                    guard let capture = WindowScreenshotService(applicationName: settings.watchedApplication).capture() else {
                        model.append(.yuki, "I can’t see a visible window for \(settings.watchedApplication) right now. Open that app and keep a window visible, then try again.")
                        model.state = .error
                        return
                    }
                    imageData = capture.png
                    outbound = "[Full \(settings.watchedApplication) window attached. Use the entire image as visual context and identify the specific thing described in the user’s question. Cursor position is only supplementary context: approximately \(Int(capture.cursor.normalizedX * 100))% from the left and \(Int(capture.cursor.normalizedY * 100))% from the top.]\n\(text)"
                }
                let reply = try await ChromeBridge.shared.send(outbound, imageData: imageData, onSubmitted: { [weak self] in
                    self?.returnFocusToWatchedApplication()
                }) { [weak model] in model?.state = .replying }
                model.append(.yuki, reply); model.state = .ready
                try? await Task.sleep(for: .milliseconds(900)); model.state = .idle
            } catch {
                model.append(.yuki, error.localizedDescription); model.state = .error
            }
        }
    }

    private func returnFocusToWatchedApplication() {
        let application = NSWorkspace.shared.runningApplications.first { $0.localizedName?.caseInsensitiveCompare(settings.watchedApplication) == .orderedSame }
        application?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    private func checkWorkChat() {
        model.state = .opening
        Task { @MainActor [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Bind Yuki’s Chrome chat"
            alert.informativeText = "Open the Yuki — App Companion conversation in Chrome, click the Yuki extension, then choose ‘Bind this tab to Yuki’."
            alert.addButton(withTitle: "Got it")
            alert.runModal()
            model.state = .idle
        }
    }

    private func resizePet(by delta: CGFloat) {
        let center = NSPoint(x: petPanel.frame.midX, y: petPanel.frame.midY)
        petSize = (petSize + delta).clamped(to: 48...128)
        petPanel.setFrame(NSRect(x: center.x - petSize / 2, y: center.y - petSize / 2, width: petSize, height: petSize), display: true)
        UserDefaults.standard.set(Double(petSize), forKey: "yuki.petSize"); savePetFrame(); repositionBubble()
    }
    private func savePetFrame() { UserDefaults.standard.set(NSStringFromRect(petPanel.frame), forKey: "yuki.petFrame") }
}

@MainActor final class CompanionModel: ObservableObject {
    @Published var messages: [YukiChatMessage] = [] { didSet { persist() } }
    @Published var draft = ""
    @Published var state: PetState = .idle
    @Published var focusComposer = 0
    @Published var includeAppWindow = false
    init() {
        if let data = UserDefaults.standard.data(forKey: "yuki.messages"), let saved = try? JSONDecoder().decode([YukiChatMessage].self, from: data) { messages = saved }
    }
    func takeDraft() -> String? {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }; draft = ""; return value
    }
    func append(_ role: YukiChatMessage.Role, _ text: String) { messages.append(YukiChatMessage(role: role, text: text)) }
    private func persist() { if let data = try? JSONEncoder().encode(Array(messages.suffix(200))) { UserDefaults.standard.set(data, forKey: "yuki.messages") } }
}

enum PetState { case idle, clicked, capturing, opening, waiting, replying, ready, error, hover, look, answerStart, answerComplete, rareIdleA, rareIdleB }

@MainActor struct PetView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var settings: CompanionSettings
    @StateObject private var animator = SpriteAnimationController()
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = animator.image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(2) } else { Color.clear }
            Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 7, weight: .bold)).foregroundStyle(.pink.opacity(0.65)).padding(4).allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onChange(of: model.state) { animator.set($0, themeID: settings.themeID) }
        .onChange(of: settings.themeID) { _ in animator.set(.idle, themeID: settings.themeID) }
        .onAppear { animator.set(model.state, themeID: settings.themeID) }
    }
}

private extension CGFloat { func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) } }
private extension NSRect {
    func fitted(to screen: NSRect, size: NSSize) -> NSRect {
        NSRect(x: min(max(origin.x, screen.minX), screen.maxX - size.width), y: min(max(origin.y, screen.minY), screen.maxY - size.height), width: size.width, height: size.height)
    }
}
