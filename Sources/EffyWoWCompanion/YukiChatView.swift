import AppKit
import SwiftUI

struct YukiChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, yuki }
    var id = UUID()
    let role: Role
    var text: String
}

@MainActor struct YukiChatView: View {
    @ObservedObject var model: CompanionModel
    let onSend: () -> Void
    let onCheckWorkChat: () -> Void
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Yuki").font(.headline).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.78))
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onCheckWorkChat) { Image(systemName: "link").foregroundStyle(.pink) }.buttonStyle(.plain).help("Open and confirm Yuki’s Work chat")
                Button("×", action: onClose).buttonStyle(.plain).font(.title2)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Color.pink.opacity(0.35))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { Text("Ask me anything, Effy 💗").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 36) }
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(message.role == .user ? "You:" : "Yuki:").font(.caption.bold()).foregroundStyle(message.role == .user ? .pink : Color(red: 1, green: 0.72, blue: 0.87))
                                Text(message.text).textSelection(.enabled)
                            }
                            .padding(10).background(message.role == .user ? Color.pink.opacity(0.18) : Color.white.opacity(0.075)).clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading).id(message.id)
                        }
                    }.padding(12)
                }
                .onChange(of: model.messages) { messages in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider().overlay(Color.pink.opacity(0.35))
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: { model.includeWoWView.toggle() }) {
                    Image(systemName: model.includeWoWView ? "eye.fill" : "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.includeWoWView ? .pink : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.includeWoWView ? "WoW view will be attached" : "Attach the current WoW view")
                ComposerTextView(text: $model.draft, focusToken: model.focusComposer, onSend: onSend).frame(minHeight: 38, maxHeight: 92)
                Button(action: onSend) { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.pink) }.buttonStyle(.plain).help("Send")
            }.padding(10)
        }
        .frame(minWidth: 300, minHeight: 260).background(.black.opacity(0.86))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.pink.opacity(0.75), lineWidth: 1.5)).clipShape(RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
    }
    private var status: String {
        switch model.state { case .waiting, .opening: "thinking…"; case .replying: "replying…"; case .error: "a little confused"; default: "" }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onSend: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let view = NSTextView(); view.delegate = context.coordinator; view.isRichText = false; view.font = .systemFont(ofSize: 14)
        view.textColor = .white; view.backgroundColor = NSColor.white.withAlphaComponent(0.08); view.textContainerInset = NSSize(width: 7, height: 7); view.string = text
        scroll.documentView = view; context.coordinator.view = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = context.coordinator.view else { return }
        if view.string != text { view.string = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken; DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView; weak var view: NSTextView?; var focusToken = -1
        init(_ parent: ComposerTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view { parent.text = view.string } }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), !NSEvent.modifierFlags.contains(.shift) else { return false }
            parent.onSend(); return true
        }
    }
}
