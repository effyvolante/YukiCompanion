import Foundation
import Network

@MainActor
final class ChromeBridge {
    static let shared = ChromeBridge()
    private let port: NWEndpoint.Port = 39173
    private var listener: NWListener?
    private var commands: [QueuedCommand] = []
    private var commandWaiters: [(connection: NWConnection, deadline: Date)] = []
    private var contexts: [String: Data] = [:]
    private var pending: [String: Pending] = [:]
    private let sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var lastBridgeStatus: Date?
    private var connectionMonitorStarted = false
    var onConnectionStateChanged: (@MainActor (BridgeConnectionState) -> Void)?

    private final class QueuedCommand {
        let payload: [String: String]
        let messageID: String?
        var leasedAt: Date?

        init(payload: [String: String], messageID: String? = nil) {
            self.payload = payload
            self.messageID = messageID
        }
    }

    private final class Pending {
        let onSubmitted: @MainActor () -> Void
        let onReply: @MainActor () -> Void
        let onPhase: @MainActor (BridgePhase) -> Void
        let onPartial: @MainActor (String) -> Void
        let continuation: CheckedContinuation<String, Error>
        var phase: BridgePhase = .queued
        var lastActivity = Date()

        init(onSubmitted: @escaping @MainActor () -> Void, onReply: @escaping @MainActor () -> Void, onPhase: @escaping @MainActor (BridgePhase) -> Void, onPartial: @escaping @MainActor (String) -> Void, continuation: CheckedContinuation<String, Error>) {
            self.onSubmitted = onSubmitted
            self.onReply = onReply
            self.onPhase = onPhase
            self.onPartial = onPartial
            self.continuation = continuation
        }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { NSLog("[YukiChrome] listener failed: %@", error.localizedDescription) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInitiated))
                self?.receive(connection, buffer: Data())
            }
            self.listener = listener
            listener.start(queue: .global(qos: .utility))
            if !connectionMonitorStarted {
                connectionMonitorStarted = true
                Task { @MainActor [weak self] in await self?.monitorConnection() }
            }
        } catch {
            NSLog("[YukiChrome] unable to start bridge: %@", error.localizedDescription)
        }
    }

    func send(id: String = UUID().uuidString, _ text: String, imageData: Data? = nil, onSubmitted: @escaping @MainActor () -> Void = {}, onPhase: @escaping @MainActor (BridgePhase) -> Void = { _ in }, onPartial: @escaping @MainActor (String) -> Void = { _ in }, onReplyDetected: @escaping @MainActor () -> Void) async throws -> String {
        start()
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let item = Pending(onSubmitted: onSubmitted, onReply: onReplyDetected, onPhase: onPhase, onPartial: onPartial, continuation: continuation)
                self.pending[id] = item
                item.onPhase(.queued)
                var command = ["type": "send_message", "id": id, "text": text, "token": self.sessionToken]
                if let imageData { self.contexts[id] = imageData; command["contextID"] = id }
                self.commands.append(QueuedCommand(payload: command, messageID: id))
                self.drainCommandWaiters()
                await self.monitorTimeout(for: id)
            }
        }
    }

    func reconnect() {
        start()
        onConnectionStateChanged?(.connecting)
        commands.append(QueuedCommand(payload: ["type": "reconnect", "token": sessionToken]))
        drainCommandWaiters()
    }

    private func monitorTimeout(for id: String) async {
        while let item = pending[id] {
            let timeout: TimeInterval = switch item.phase {
            case .queued: 30
            case .delivered: 45
            case .submitted: 150
            case .responding: 300
            case .completed, .failed: 1
            }
            if Date().timeIntervalSince(item.lastActivity) >= timeout {
                pending.removeValue(forKey: id)
                acknowledgeCommand(id)
                contexts.removeValue(forKey: id)
                item.onPhase(.failed)
                item.continuation.resume(throwing: ChromeBridgeError.message(timeoutMessage(for: item.phase)))
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func monitorConnection() async {
        while listener != nil {
            if let lastBridgeStatus, Date().timeIntervalSince(lastBridgeStatus) > 45 {
                onConnectionStateChanged?(.disconnected)
            }
            try? await Task.sleep(for: .seconds(3))
        }
        connectionMonitorStarted = false
    }

    private func timeoutMessage(for phase: BridgePhase) -> String {
        switch phase {
        case .queued: "Yuki couldn’t reach the browser extension. Open the bound ChatGPT tab, then choose Reconnect ChatGPT."
        case .delivered: "ChatGPT received the message but did not confirm submission."
        case .submitted: "ChatGPT accepted the message but did not begin a response."
        case .responding: "ChatGPT stopped updating its response."
        case .completed, .failed: "Yuki’s browser connection stopped unexpectedly."
        }
    }

    private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            let combined = buffer + (data ?? Data())
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let request = self.parseRequest(combined) {
                    self.respond(to: connection, request: request)
                } else if !isComplete && error == nil {
                    self.receive(connection, buffer: combined)
                }
            }
        }
    }

    private func parseRequest(_ data: Data) -> (method: String, path: String, body: Data, token: String?)? {
        guard let separator = data.range(of: Data([13, 10, 13, 10])) else { return nil }
        let headerData = data[..<separator.lowerBound]
        guard let headers = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headers.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let length = lines.dropFirst().first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0") } ?? 0
        let bodyStart = separator.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let token = lines.dropFirst().first { $0.lowercased().hasPrefix("x-yuki-bridge-token:") }.map { String($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "" ) }
        return (String(parts[0]), String(parts[1]), data[bodyStart..<bodyStart + length], token)
    }

    private func respond(to connection: NWConnection, request: (method: String, path: String, body: Data, token: String?)) {
        if request.method == "OPTIONS" { write(connection, status: "204 No Content", body: Data()); return }
        if request.method == "GET" && request.path == "/session" { writeJSON(connection, ["token": sessionToken]); return }
        let protected = request.path.hasPrefix("/commands") || request.path == "/events" || request.path.hasPrefix("/context/")
        guard !protected || request.token == sessionToken else { writeJSON(connection, ["error": "unauthorized"], status: "401 Unauthorized"); return }
        if request.method == "GET" && request.path.hasPrefix("/commands") {
            if !respondWithNextCommand(to: connection) {
                let wait = min(max(commandWaitSeconds(from: request.path), 0), 25)
                if wait == 0 { writeJSON(connection, ["type": "idle"]) }
                else {
                    commandWaiters.append((connection, Date().addingTimeInterval(wait)))
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(wait + 1))
                        self?.drainExpiredCommandWaiters()
                    }
                }
            }
            return
        }
        if request.method == "GET", request.path.hasPrefix("/context/") {
            let id = String(request.path.dropFirst("/context/".count))
            guard let data = contexts[id] else { write(connection, status: "404 Not Found", body: Data()); return }
            write(connection, status: "200 OK", body: data, contentType: "image/png"); return
        }
        if request.method == "POST" && request.path == "/events" {
            if let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] { handleEvent(object) }
            writeJSON(connection, ["ok": true]); return
        }
        write(connection, status: "404 Not Found", body: Data("not found".utf8))
    }

    private func commandWaitSeconds(from path: String) -> TimeInterval {
        guard let question = path.firstIndex(of: "?") else { return 0 }
        let query = path[path.index(after: question)...]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.first == "wait", let value = parts.last, let seconds = Double(value) { return seconds }
        }
        return 0
    }

    private func respondWithNextCommand(to connection: NWConnection) -> Bool {
        let now = Date()
        guard let index = commands.firstIndex(where: { $0.leasedAt == nil || now.timeIntervalSince($0.leasedAt!) >= 10 }) else { return false }
        let queued = commands[index]
        queued.leasedAt = now
        let command = queued.payload
        if queued.messageID == nil { commands.remove(at: index) }
        writeJSON(connection, command)
        return true
    }

    private func drainCommandWaiters() {
        guard !commandWaiters.isEmpty else { return }
        var remaining: [(connection: NWConnection, deadline: Date)] = []
        for waiter in commandWaiters {
            if respondWithNextCommand(to: waiter.connection) { continue }
            remaining.append(waiter)
        }
        commandWaiters = remaining
    }

    private func drainExpiredCommandWaiters() {
        let now = Date()
        var remaining: [(connection: NWConnection, deadline: Date)] = []
        for waiter in commandWaiters {
            if respondWithNextCommand(to: waiter.connection) { continue }
            if waiter.deadline <= now { writeJSON(waiter.connection, ["type": "idle"]) }
            else { remaining.append(waiter) }
        }
        commandWaiters = remaining
    }

    private func handleEvent(_ object: [String: Any]) {
        if object["type"] as? String == "bridge_status", let state = object["state"] as? String {
            lastBridgeStatus = Date()
            onConnectionStateChanged?(state == "ready" ? .ready : .needsBinding)
            return
        }
        guard let id = object["id"] as? String, let type = object["type"] as? String, let item = pending[id] else { return }
        if type == "status", let state = object["state"] as? String {
            if state == "delivered" { update(item, phase: .delivered); return }
            if state == "submitted" { acknowledgeCommand(id); update(item, phase: .submitted); item.onSubmitted(); return }
        }
        if type == "response_update" {
            update(item, phase: .responding)
            item.onReply()
            if let text = object["text"] as? String, !text.isEmpty { item.onPartial(text) }
            return
        }
        if type == "response_complete", let text = object["text"] as? String {
            acknowledgeCommand(id)
            pending.removeValue(forKey: id)
            contexts.removeValue(forKey: id)
            item.onPhase(.completed)
            item.continuation.resume(returning: text)
        } else if type == "error" {
            acknowledgeCommand(id)
            pending.removeValue(forKey: id)
            contexts.removeValue(forKey: id)
            item.onPhase(.failed)
            let message = object["message"] as? String ?? "Chrome could not complete the Yuki chat."
            item.continuation.resume(throwing: ChromeBridgeError.message(message))
        }
    }

    private func acknowledgeCommand(_ id: String) {
        commands.removeAll { $0.messageID == id }
    }

    private func update(_ item: Pending, phase: BridgePhase) {
        item.phase = phase
        item.lastActivity = Date()
        item.onPhase(phase)
    }

    private func writeJSON(_ connection: NWConnection, _ object: [String: Any], status: String = "200 OK") {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        write(connection, status: status, body: data, contentType: "application/json")
    }

    private func write(_ connection: NWConnection, status: String, body: Data, contentType: String = "text/plain") {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: content-type, x-yuki-bridge-token\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum BridgePhase: String, Codable { case queued, delivered, submitted, responding, completed, failed }
enum BridgeConnectionState: String { case connecting, ready, needsBinding, disconnected }

enum ChromeBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
