import AppKit
import ApplicationServices

@MainActor final class ChatGPTAppController {
    static let shared = ChatGPTAppController()
    private let defaultChatTitle = "Yuki — App Companion"
    private var boundWindow: AXUIElement?
    private var boundComposer: AXUIElement?
    private var boundSendButton: AXUIElement?
    private var boundPID: pid_t?
    private var sending = false

    private func bridgeLog(_ message: String) {
        let line = "[YukiBridge] " + message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/yuki-bridge.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    func prepareBoundChat() async throws {
        guard AXIsProcessTrusted() else { throw YukiBridgeError.accessibility }
        // Bind the currently selected conversation; pressing a sidebar item can
        // cause ChatGPT to restore its window even without activating the app.
        let (app, root) = try await openChatGPT(foreground: false)
        let title = UserDefaults.standard.string(forKey: "yuki.chatTitle") ?? defaultChatTitle
        guard findConversation(in: root, matching: title) != nil else { throw YukiBridgeError.boundChatMissing }
        guard let composer = findComposer(in: root), let window = element(composer, kAXWindowAttribute) else { throw YukiBridgeError.noComposer }
        boundWindow = window
        boundComposer = composer
        boundSendButton = findSendButton(in: window)
        boundPID = app.processIdentifier
    }

    func send(_ message: String, onReplyDetected: @escaping @MainActor () -> Void) async throws -> String {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else { throw YukiBridgeError.accessibility }
        guard !sending else { throw YukiBridgeError.busy }
        sending = true
        defer { sending = false }
        guard let boundRoot = boundWindow, let boundComposer, let pid = boundPID,
              let app = NSRunningApplication(processIdentifier: pid) else { throw YukiBridgeError.needsBinding }
        let previous = NSWorkspace.shared.frontmostApplication
        bridgeLog("ChatGPT running; text path = AccessibilityDirectValue; pasteboard used for text = false")
        if let minimized = boolean(boundRoot, kAXMinimizedAttribute) { bridgeLog("Bound window minimized=\(minimized)") }

        // Keep ChatGPT alive and unminimized so its web accessibility tree stays
        // valid, but never make it the visible foreground interface.
        if boolean(boundRoot, kAXMinimizedAttribute) == true {
            _ = AXUIElementSetAttributeValue(boundRoot, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            try await Task.sleep(for: .milliseconds(500))
        }

        let application = AXUIElementCreateApplication(pid)
        let root = conversationWindow(in: application) ?? boundRoot
        let composer = findComposer(in: root) ?? boundComposer
        let baselineAssistantReplies = assistantReplies(in: root)
        bridgeLog("Live composer located")
        var submissionRoot = root
        var submissionComposer = composer
        var exactTextReady = setComposerTextExactly(message, composer: composer)
        if !exactTextReady {
            // ChatGPT's web composer may reject AXValue while it is behind another app.
            // Briefly activate only to obtain a verified focused composer; the
            // previous foreground app is restored immediately after submission.
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            try await Task.sleep(for: .milliseconds(350))
            submissionRoot = windows(of: application).first(where: { findComposer(in: $0) != nil }) ?? root
            guard let refreshed = findComposer(in: submissionRoot) else {
                bridgeLog("No live composer after brief activation")
                throw YukiBridgeError.noComposer
            }
            submissionComposer = refreshed
            exactTextReady = setComposerTextExactly(message, composer: refreshed) ||
                setComposerTextWithIsolatedPasteboard(message, composer: refreshed, application: application, pid: pid)
        }
        guard exactTextReady else {
            bridgeLog("Exact message verification FAILED; refusing to submit")
            throw YukiBridgeError.cannotWrite
        }
        bridgeLog("Exact message inserted; composer verification PASS")
        let before = baselineAssistantReplies
        try await Task.sleep(for: .milliseconds(250))
        var submitted = false
        var submissionAttempted = false
        // Re-query after insertion because ChatGPT can rerender the composer.
        var submitRoot = windows(of: application).first(where: { findComposer(in: $0) != nil }) ?? submissionRoot
        var submitComposer = findComposer(in: submitRoot) ?? submissionComposer
        if let sendButton = findSendButton(in: submitRoot) {
            submissionAttempted = true
            if AXUIElementPerformAction(sendButton, kAXPressAction as CFString) == .success {
            bridgeLog("Send control reacquired; AXPress attempted")
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(250))
                if composerLooksSubmitted(submitComposer) || assistantReplies(in: submitRoot).count > before.count { submitted = true; break }
            }
            }
        }
        if !submitted {
            submissionAttempted = true
        }
        if !submitted, AXUIElementPerformAction(submitComposer, kAXConfirmAction as CFString) == .success {
            bridgeLog("AXConfirm attempted")
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(250))
                if composerLooksSubmitted(submitComposer) || assistantReplies(in: submitRoot).count > before.count { submitted = true; break }
            }
        }
        if !submitted {
            // Final fallback: only send Return after positively focusing the
            // exact composer containing the exact requested message.
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            try await Task.sleep(for: .milliseconds(180))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                try await Task.sleep(for: .milliseconds(500))
                submitRoot = windows(of: application).first(where: { findComposer(in: $0) != nil }) ?? submitRoot
                submitComposer = findComposer(in: submitRoot) ?? submitComposer
            }
            let focusVerified = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid &&
                AXUIElementSetAttributeValue(submitRoot, kAXMainAttribute as CFString, kCFBooleanTrue) == .success &&
                AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success &&
                AXUIElementSetAttributeValue(application, kAXFocusedUIElementAttribute as CFString, submitComposer) == .success &&
                isApplicationFocused(application, submitComposer) &&
                value(of: submitComposer).map({ normalizeComposerText($0) == normalizeComposerText(message) }) == true
            if !focusVerified {
                bridgeLog("Composer focus/value verification FAILED; refusing keyboard fallback")
                if !submissionAttempted { throw YukiBridgeError.cannotSubmit }
                bridgeLog("Submission state unknown; continuing response polling")
                submitted = true
                previous?.activate(options: [.activateIgnoringOtherApps])
                // The response polling below remains authoritative.
            } else {
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else { throw YukiBridgeError.cannotSubmit }
                bridgeLog("Verified frontmost ChatGPT composer focus; Return fallback attempted")
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                for _ in 0..<12 {
                    try await Task.sleep(for: .milliseconds(250))
                    if composerLooksSubmitted(submitComposer) || assistantReplies(in: submitRoot).count > before.count { submitted = true; break }
                }
            }
        }
        guard submitted || submissionAttempted else { bridgeLog("Submission could not be attempted"); throw YukiBridgeError.cannotSubmit }
        bridgeLog(submitted ? "Submission verified" : "Submission probable; response polling continues")
        previous?.activate(options: [.activateIgnoringOtherApps])
        var lastCandidate = "", stableCount = 0, announced = false
        for poll in 0..<180 {
            try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(500))
            // Every poll starts from a fresh application/window/tree query.
            let freshApplication = AXUIElementCreateApplication(pid)
            let freshWindows = windows(of: freshApplication)
            var candidate: String?
            var replyCount = 0
            var anchorFound = false
            for freshRoot in freshWindows {
                let freshReplies = assistantReplies(in: freshRoot)
                replyCount += freshReplies.count
                anchorFound = anchorFound || containsExactText(freshRoot, message)
                if candidate == nil { candidate = newestAssistantReply(in: freshRoot, after: message) }
                if candidate == nil, freshReplies.count > baselineAssistantReplies.count { candidate = freshReplies.last }
            }
            if poll % 10 == 0 { bridgeLog("Response poll windows=\(freshWindows.count) replies=\(replyCount) anchor=\(anchorFound) candidate=\(candidate != nil)") }
            guard let candidate, !candidate.isEmpty else { continue }
            if !announced { announced = true; onReplyDetected() }
            if normalizeForComparison(candidate) == normalizeForComparison(lastCandidate) { stableCount += 1 } else { lastCandidate = candidate; stableCount = 0 }
            if stableCount >= 4 {
                return candidate
            }
        }
        throw YukiBridgeError.replyUnavailable
    }

    private func openChatGPT(foreground: Bool) async throws -> (NSRunningApplication, AXUIElement) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.chat") ?? workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") else { throw YukiBridgeError.notInstalled }
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.openai.codex"
        let app: NSRunningApplication
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app = running }
        else { let config = NSWorkspace.OpenConfiguration(); config.activates = foreground; app = try await workspace.openApplication(at: url, configuration: config) }
        if foreground { app.unhide(); app.activate(options: [.activateIgnoringOtherApps]) }
        try await Task.sleep(for: .milliseconds(900))
        return (app, AXUIElementCreateApplication(app.processIdentifier))
    }
    private func findComposer(in root: AXUIElement) -> AXUIElement? {
        let candidates = descendants(of: root, limit: 1800).filter { element in
            let role = string(element, kAXRoleAttribute)
            return (role == kAXTextAreaRole as String || role == kAXTextFieldRole as String || role == kAXComboBoxRole as String) && isSettable(element, kAXValueAttribute)
        }
        return candidates.last(where: { element in
            let label = (string(element, kAXDescriptionAttribute) + " " + string(element, kAXPlaceholderValueAttribute) + " " + string(element, kAXHelpAttribute)).lowercased()
            return label.contains("message") || label.contains("ask") || label.contains("chat") || label.contains("prompt")
        })
    }
    private func findSendButton(in root: AXUIElement) -> AXUIElement? {
        descendants(of: root, limit: 1800).first { element in
            guard string(element, kAXRoleAttribute) == kAXButtonRole as String, canPress(element) else { return false }
            return [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute].contains { attribute in
                ["send", "send message", "send prompt", "submit", "submit message", "send-button"].contains(string(element, attribute).lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
    private func currentValue(of element: AXUIElement) -> String {
        string(element, kAXValueAttribute)
    }
    private func find(in root: AXUIElement, roles: Set<String>, matching text: String) -> AXUIElement? {
        descendants(of: root, limit: 600).first { element in
            roles.contains(string(element, kAXRoleAttribute)) && [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].contains { attribute in string(element, attribute) == text }
        }
    }
    private func findConversation(in root: AXUIElement, matching title: String) -> AXUIElement? {
        let wanted = normalize(title)
        return descendants(of: root, limit: 1800).first { element in
            guard canPress(element) else { return false }
            let values = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map { string(element, $0) }
            return values.contains { normalize($0) == wanted || normalize($0).contains(wanted) }
        }
    }
    private func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success, let actions = actions as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
    }
    private func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "–", with: "-").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func descendants(of root: AXUIElement, limit: Int) -> [AXUIElement] {
        var queue = [root], result: [AXUIElement] = []
        var visited = Set<AXUIElement>()
        while !queue.isEmpty && result.count < limit {
            let next = queue.removeFirst()
            guard visited.insert(next).inserted else { continue }
            result.append(next)
            for attribute in [kAXChildrenAttribute, kAXWindowsAttribute, kAXContentsAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(next, attribute as CFString, &value) == .success, let children = value as? [AXUIElement] { queue.append(contentsOf: children) }
            }
        }
        return result
    }
    private func windows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let items = value as? [AXUIElement] else { return [] }
        return items
    }
    private func conversationWindow(in application: AXUIElement, containing message: String? = nil) -> AXUIElement? {
        let all = windows(of: application)
        if let message {
            if let match = all.first(where: { containsExactText($0, message) }) { return match }
        }
        return all.first(where: { findComposer(in: $0) != nil }) ?? all.first
    }
    private func containsExactText(_ root: AXUIElement, _ expected: String) -> Bool {
        descendants(of: root, limit: 6000).contains { node in
            let role = string(node, kAXRoleAttribute)
            return role == kAXStaticTextRole as String && normalizeForComparison(value(of: node) ?? "") == normalizeForComparison(expected)
        }
    }
    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
    private func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private func value(of source: AXUIElement) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, kAXValueAttribute as CFString, &result) == .success else { return nil }
        if let text = result as? String { return text }
        return (result as? NSAttributedString)?.string
    }
    private func composerText(_ source: AXUIElement) -> String? {
        // Some rich-text editors omit AXValue for an empty document but still
        // expose its character count. Missing data alone never proves a draft.
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(source, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let number = count as? NSNumber, number.intValue == 0 { return "" }
        return value(of: source)
    }
    private func normalizeComposerText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
    private func normalizeForComparison(_ text: String) -> String {
        normalizeComposerText(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func setComposerTextExactly(_ message: String, composer: AXUIElement) -> Bool {
        guard AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, message as CFTypeRef) == .success else { return false }
        guard let actual = composerText(composer) else { return false }
        return normalizeComposerText(actual) == normalizeComposerText(message)
    }
    private func setComposerTextWithIsolatedPasteboard(_ message: String, composer: AXUIElement, application: AXUIElement, pid: pid_t) -> Bool {
        guard AXUIElementSetAttributeValue(application, kAXFocusedUIElementAttribute as CFString, composer) == .success,
              isApplicationFocused(application, composer) else { return false }
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(message, forType: .string),
              let source = CGEventSource(stateID: .hidSystemState),
              let selectDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let selectUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false),
              let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        let command = CGEventFlags.maskCommand
        selectDown.flags = command; selectUp.flags = command
        pasteDown.flags = command; pasteUp.flags = command
        selectDown.postToPid(pid); selectUp.postToPid(pid)
        pasteDown.postToPid(pid); pasteUp.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.2)
        guard let actual = composerText(composer) else { return false }
        let exact = normalizeComposerText(actual) == normalizeComposerText(message)
        bridgeLog(exact ? "Text fallback exact verification PASS; clipboard restored" : "Text fallback exact verification FAILED")
        return exact
    }
    private func composerLooksSubmitted(_ source: AXUIElement) -> Bool {
        guard let text = composerText(source) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func isFocused(_ source: AXUIElement) -> Bool {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, kAXFocusedAttribute as CFString, &result) == .success else { return false }
        if let flag = result as? Bool { return flag }
        return (result as? NSNumber)?.boolValue == true
    }
    private func isApplicationFocused(_ application: AXUIElement, _ expected: AXUIElement) -> Bool {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &result) == .success,
              let actual = result, CFGetTypeID(actual) == AXUIElementGetTypeID() else { return false }
        return CFEqual(actual, expected)
    }
    private func pasteIntoFocusedComposer(_ text: String, pid: pid_t) throws {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string),
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw YukiBridgeError.cannotWrite }
        let command = CGEventFlags.maskCommand
        down.flags = command; up.flags = command
        down.postToPid(pid); up.postToPid(pid)
    }
    func clearBinding() { boundWindow = nil; boundPID = nil }
    private func boolean(_ source: AXUIElement, _ attribute: String) -> Bool? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &result) == .success else { return nil }
        return result as? Bool
    }
    // Only a labeled assistant message can contribute reply text. Generic window
    // labels and newly appearing sidebar text are never treated as an answer.
    private func assistantReplies(in root: AXUIElement) -> [String] {
        let nodes = descendants(of: root, limit: 6000)
        var replies: [String] = []
        var parts: [String] = []
        var collecting = false
        func finish() {
            let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 2 { replies.append(text) }
            parts.removeAll(keepingCapacity: true)
        }
        for node in nodes {
            let role = string(node, kAXRoleAttribute)
            let heading = role == "AXHeading" ? string(node, kAXTitleAttribute) : ""
            let text = role == kAXStaticTextRole as String ? (value(of: node) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if heading == "You said:" || text == "You said:" {
                if collecting { finish() }
                collecting = false
                continue
            }
            if heading == "ChatGPT said:" || text == "ChatGPT said:" {
                if collecting { finish() }
                collecting = true
                continue
            }
            if collecting && ["Unread", "Personal life OS design", "Work with ChatGPT", "Approve for me"].contains(text) {
                finish()
                collecting = false
                continue
            }
            if collecting, role == kAXStaticTextRole as String,
               text.count >= 2, !isInterfaceLabel(text), !isTimestamp(text) {
                parts.append(text)
            }
        }
        if collecting { finish() }
        return replies
    }
    private func isTimestamp(_ value: String) -> Bool {
        value.range(of: "^\\d{1,2}:\\d{2} (AM|PM)$", options: .regularExpression) != nil
    }
    private func newestAssistantReply(in root: AXUIElement, after userMessage: String) -> String? {
        let nodes = descendants(of: root, limit: 6000)
        var ordered: [(role: String, text: String)] = []
        for node in nodes {
            let role = string(node, kAXRoleAttribute)
            if role == "AXHeading" {
                ordered.append((role, string(node, kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)))
            } else if role == kAXStaticTextRole as String, let text = value(of: node) {
                ordered.append((role, text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        guard let userIndex = ordered.lastIndex(where: { $0.text == userMessage }) else { return nil }
        var started = false
        var parts: [String] = []
        for item in ordered[(userIndex + 1)...] {
            if item.text == "You said:" { break }
            if item.text == "ChatGPT said:" { started = true; continue }
            if !started { continue }
            if ["Unread", "Personal life OS design", "Work with ChatGPT", "Approve for me"].contains(item.text) { break }
            if item.text == "Response started" || item.text == "Worked for 5s" || isTimestamp(item.text) || isInterfaceLabel(item.text) { continue }
            if item.role == kAXStaticTextRole as String, item.text.count >= 2 { parts.append(item.text) }
        }
        let result = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
    private func readableText(in root: AXUIElement) -> [String] {
        descendants(of: root, limit: 900).compactMap { element in
            let role = string(element, kAXRoleAttribute)
            let readableRoles: [String] = [kAXStaticTextRole as String, kAXTextAreaRole as String, "AXWebArea", "AXHeading"]
            guard readableRoles.contains(role) else { return nil }
            let value = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .map { string(element, $0) }
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
    }
    private func isInterfaceLabel(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["stop generating", "new chat", "send message", "copy", "regenerate", "chatgpt", "settings", "user messages", "assistant messages", "message history", "conversation history"].contains(lower)
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }; return value as? String ?? ""
    }
}

private enum YukiBridgeError: LocalizedError {
    case accessibility, notInstalled, boundChatMissing, boundChatUnavailable, noComposer, cannotWrite, notFocused, cannotSubmit, replyUnavailable, needsBinding, busy
    var errorDescription: String? {
        switch self {
        case .needsBinding: "Click Yuki’s link button once to select the Work chat before sending."
        case .busy: "Yuki is still waiting for the previous message."
        case .accessibility: "Yuki needs Accessibility permission. Enable Yuki Companion in System Settings → Privacy & Security → Accessibility."
        case .notInstalled: "ChatGPT isn’t installed."
        case .boundChatMissing: "Open or create a ChatGPT chat named ‘Yuki — App Companion’, then try again. Yuki stopped safely so she wouldn’t send your message to the wrong conversation."
        case .boundChatUnavailable: "Yuki found ‘Yuki — App Companion’, but ChatGPT wouldn’t open it. Open that chat manually once, then try again."
        case .noComposer: "I couldn’t find the ChatGPT message box. Open your ‘Yuki — App Companion’ chat once, then try again."
        case .cannotWrite: "ChatGPT’s message box wouldn’t accept Yuki’s message."
        case .notFocused: "Yuki stopped safely because ChatGPT was not focused."
        case .cannotSubmit: "Yuki placed the message in ChatGPT but couldn’t safely submit it."
        case .replyUnavailable: "ChatGPT received your message, but its reply wasn’t exposed to Yuki. Open ChatGPT to read this answer."
        }
    }
}
