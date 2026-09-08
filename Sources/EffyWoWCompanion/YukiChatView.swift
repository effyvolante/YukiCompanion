import AppKit
import SwiftUI

struct YukiChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, yuki }
    enum DeliveryState: String, Codable { case queued, delivered, submitted, responding, completed, failed }
    var id = UUID()
    let role: Role
    var text: String
    var deliveryState: DeliveryState? = nil
}

@MainActor struct YukiChatView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var settings: CompanionSettings
    var companionName = "Yuki"
    let onSend: () -> Void
    let onCheckWorkChat: () -> Void
    let onCheckForUpdates: () -> Void
    let onProvideFeedback: () -> Void
    let onOpenMenu: () -> Void
    let onClose: () -> Void

    init(model: CompanionModel, settings: CompanionSettings, companionName: String = "Yuki", onSend: @escaping () -> Void, onCheckWorkChat: @escaping () -> Void, onCheckForUpdates: @escaping () -> Void = {}, onProvideFeedback: @escaping () -> Void = {}, onOpenMenu: @escaping () -> Void = {}, onClose: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.companionName = companionName
        self.onSend = onSend
        self.onCheckWorkChat = onCheckWorkChat
        self.onCheckForUpdates = onCheckForUpdates
        self.onProvideFeedback = onProvideFeedback
        self.onOpenMenu = onOpenMenu
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(companionName).font(.headline).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.78))
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenMenu()
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
                .help("Yuki menu")
                Button(action: onCheckWorkChat) { Image(systemName: "link").foregroundStyle(.pink) }.buttonStyle(.plain).help("Open and confirm Yuki’s App Companion chat")
                Button("×", action: onClose).buttonStyle(.plain).font(.title2)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Color.pink.opacity(0.35))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { Text("Ask me anything, Effy 💗").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 36) }
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(message.role == .user ? "You:" : "\(companionName):").font(.caption.bold()).foregroundStyle(message.role == .user ? .pink : Color(red: 1, green: 0.72, blue: 0.87))
                                Text(renderedText(message.text)).textSelection(.enabled)
                                if message.role == .user, let delivery = message.deliveryState, delivery != .completed {
                                    HStack(spacing: 6) {
                                        Text(delivery.label).font(.caption2).foregroundStyle(delivery == .failed ? .red : .secondary)
                                        if delivery == .failed {
                                            Button("Retry") { model.restoreDraft(from: message.id) }
                                                .buttonStyle(.borderless).font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(10).background(message.role == .user ? Color.pink.opacity(0.18) : Color.white.opacity(0.075)).clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading).id(message.id)
                        }
                    }.padding(12)
                }
                .onChange(of: model.messages.map(\.id)) { ids in if let id = ids.last { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider().overlay(Color.pink.opacity(0.35))
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: { model.includeAppWindow.toggle() }) {
                    Image(systemName: model.includeAppWindow ? "eye.fill" : "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.includeAppWindow ? .pink : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.includeAppWindow ? "App window will be attached" : "Attach the selected app window")
                ComposerTextView(text: $model.draft, focusToken: model.focusComposer, onSend: onSend).frame(minHeight: 38, maxHeight: 92)
                Button(action: onSend) { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.pink) }.buttonStyle(.plain).help("Send")
            }.padding(10)
        }
        .frame(minWidth: 300, minHeight: 260).background(.black.opacity(0.86))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.pink.opacity(0.75), lineWidth: 1.5)).clipShape(RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
    }
    private func renderedText(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }
    private var status: String {
        switch model.state {
        case .waiting, .opening: "Connecting…"
        case .replying: "Yuki is replying…"
        case .error: "Needs attention"
        default:
            switch model.connectionState {
            case .connecting: "Connecting…"
            case .ready: "Ready"
            case .needsBinding: "Needs extension"
            case .disconnected: "Disconnected"
            }
        }
    }
}

private extension YukiChatMessage.DeliveryState {
    var label: String {
        switch self {
        case .queued: "Sending…"
        case .delivered: "Delivered"
        case .submitted: "Sent"
        case .responding: "Yuki is replying…"
        case .completed: ""
        case .failed: "Needs attention"
        }
    }
}

@MainActor
private struct YukiMenuView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var settings: CompanionSettings
    let onCheckWorkChat: () -> Void
    let onReconnect: () -> Void
    let onCheckForUpdates: () -> Void
    let onProvideFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yuki menu").font(.headline).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.78))
            Divider().overlay(Color.pink.opacity(0.35))
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection").font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    Circle().fill(connectionColor).frame(width: 7, height: 7)
                    Text(connectionLabel).font(.caption)
                    Spacer()
                    Button("Reconnect", action: onReconnect).buttonStyle(.borderless)
                }
            }
            Divider().overlay(Color.pink.opacity(0.35))
            Button {
                SetupGuideWindowController.shared.show()
            } label: {
                MenuLabel(title: "Get started", detail: "Set up Yuki from beginning to end")
            }
            .buttonStyle(.plain)
            Toggle(isOn: $settings.automaticLook) {
                MenuLabel(title: "Automatic Look", detail: "Attach context for visual questions")
            }
            Toggle(isOn: $settings.launchAtLogin) {
                MenuLabel(title: "Launch at login", detail: "Start Yuki when you sign in")
            }
            Button {
                model.includeAppWindow = true
            } label: {
                MenuLabel(title: "Attach app window", detail: settings.watchedApplication)
            }
            .buttonStyle(.plain)
            Divider().overlay(Color.pink.opacity(0.35))
            Button {
                SettingsWindowController.shared.show()
            } label: {
                MenuLabel(title: "Settings…", detail: "Name, app, conversation, startup")
            }
            .buttonStyle(.plain)
            Button {
                PermissionsWindowController.shared.show()
            } label: {
                MenuLabel(title: "Permissions…", detail: "Accessibility and Screen Recording")
            }
            .buttonStyle(.plain)
            Button(action: onCheckForUpdates) {
                MenuLabel(title: "Check for updates", detail: "Download the matching GitHub release")
            }
            .buttonStyle(.plain)
            Button(action: onProvideFeedback) {
                MenuLabel(title: "Send feedback", detail: "Open the public feedback form")
            }
            .buttonStyle(.plain)
            Button(action: onCheckWorkChat) {
                MenuLabel(title: "Check Chrome binding", detail: settings.chromeConversation)
            }
            .buttonStyle(.plain)
            Text("ChatGPT is connected through your bound Chrome tab.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .foregroundStyle(.white)
        .background(.black.opacity(0.94))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.pink.opacity(0.75), lineWidth: 1.25))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private var connectionLabel: String {
        switch model.connectionState { case .connecting: "Connecting"; case .ready: "Ready"; case .needsBinding: "Needs extension"; case .disconnected: "Disconnected" }
    }
    private var connectionColor: Color {
        switch model.connectionState { case .ready: .green; case .connecting: .yellow; case .needsBinding, .disconnected: .pink }
    }
}

private struct MenuLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onSend: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let view = NSTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.font = .systemFont(ofSize: 14)
        view.textColor = .white
        view.insertionPointColor = .white
        view.typingAttributes = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14)]
        view.backgroundColor = NSColor.white.withAlphaComponent(0.08)
        view.drawsBackground = true
        view.textContainerInset = NSSize(width: 7, height: 7)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.string = text
        applyVisibleTextAttributes(to: view)
        scroll.documentView = view; context.coordinator.view = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // NSViewRepresentable reuses the coordinator. Refresh its bindings and
        // callbacks on every SwiftUI update; otherwise a long-lived composer
        // can keep an older binding and appear visually stale until restart.
        context.coordinator.parent = self
        guard let view = context.coordinator.view else { return }
        view.textColor = .white
        view.insertionPointColor = .white
        view.typingAttributes = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14)]
        applyVisibleTextAttributes(to: view)
        if view.string != text {
            let selectedRange = view.selectedRange()
            context.coordinator.isSynchronizing = true
            view.string = text
            context.coordinator.isSynchronizing = false
            let location = min(selectedRange.location, (text as NSString).length)
            view.setSelectedRange(NSRange(location: location, length: 0))
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            view.needsDisplay = true
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken; DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
    private func applyVisibleTextAttributes(to view: NSTextView) {
        let range = NSRange(location: 0, length: view.textStorage?.length ?? 0)
        guard range.length > 0 else { return }
        view.textStorage?.addAttributes([
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14)
        ], range: range)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var view: NSTextView?
        var focusToken = -1
        var isSynchronizing = false
        init(_ parent: ComposerTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !isSynchronizing, let view else { return }
            parent.text = view.string
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), !NSEvent.modifierFlags.contains(.shift) else { return false }
            parent.onSend(); return true
        }
    }
}
