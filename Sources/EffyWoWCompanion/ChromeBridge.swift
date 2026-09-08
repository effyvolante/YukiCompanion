import Foundation
import Network

@MainActor
final class ChromeBridge {
    static let shared = ChromeBridge()
    private let port: NWEndpoint.Port = 39173
    private var listener: NWListener?
    private var commands: [[String: String]] = []
    private var contexts: [String: Data] = [:]
    private var pending: [String: Pending] = [:]
    private let sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private struct Pending {
        let onSubmitted: @MainActor () -> Void
        let onReply: @MainActor () -> Void
        let continuation: CheckedContinuation<String, Error>
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
        } catch {
            NSLog("[YukiChrome] unable to start bridge: %@", error.localizedDescription)
        }
    }

    func send(_ text: String, imageData: Data? = nil, onSubmitted: @escaping @MainActor () -> Void = {}, onReplyDetected: @escaping @MainActor () -> Void) async throws -> String {
        start()
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pending[id] = Pending(onSubmitted: onSubmitted, onReply: onReplyDetected, continuation: continuation)
                var command = ["type": "send_message", "id": id, "text": text, "token": self.sessionToken]
                if let imageData { self.contexts[id] = imageData; command["contextID"] = id }
                self.commands.append(command)
                try? await Task.sleep(for: .seconds(120))
                guard let item = self.pending.removeValue(forKey: id) else { return }
                self.contexts.removeValue(forKey: id)
                item.continuation.resume(throwing: ChromeBridgeError.message("Yuki’s Chrome bridge did not return a response."))
            }
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
        let protected = request.path == "/commands" || request.path == "/events" || request.path.hasPrefix("/context/")
        guard !protected || request.token == sessionToken else { writeJSON(connection, ["error": "unauthorized"], status: "401 Unauthorized"); return }
        if request.method == "GET" && request.path == "/commands" {
            let command = commands.isEmpty ? ["type": "idle"] : commands.removeFirst()
            writeJSON(connection, command); return
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

    private func handleEvent(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let type = object["type"] as? String, let item = pending[id] else { return }
        if type == "status", object["state"] as? String == "submitted" { item.onSubmitted(); return }
        if type == "response_update" { item.onReply(); return }
        if type == "response_complete", let text = object["text"] as? String {
            pending.removeValue(forKey: id)
            contexts.removeValue(forKey: id)
            item.continuation.resume(returning: text)
        } else if type == "error" {
            pending.removeValue(forKey: id)
            contexts.removeValue(forKey: id)
            let message = object["message"] as? String ?? "Chrome could not complete the Yuki chat."
            item.continuation.resume(throwing: ChromeBridgeError.message(message))
        }
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

enum ChromeBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}
