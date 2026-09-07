import Foundation

struct CompanionTheme: Identifiable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let folders: [String: String]

    var menuLabel: String {
        isBeta ? "\(displayName) — BETA · \(description)" : "\(displayName) — \(description)"
    }

    var isBeta: Bool { id == "Peaches" }

    static let standardFolders: [String: String] = [
        "idle": "Idle", "blink": "Idle", "click": "Click", "hover": "Look",
        "thinking": "Thinking", "replying": "Replying", "answerStart": "AnswerStart",
        "answerComplete": "AnswerComplete", "look": "Look", "error": "Error",
        "rareIdleA": "RareIdle", "rareIdleB": "RareIdle"
    ]

    static let all: [CompanionTheme] = [
        CompanionTheme(id: "Yuki", displayName: "Yuki", description: "Pink octopus", folders: standardFolders),
        CompanionTheme(id: "Mochi", displayName: "Mochi", description: "Lavender axolotl", folders: standardFolders),
        CompanionTheme(id: "Pippin", displayName: "Pippin", description: "Mint slime cat", folders: standardFolders),
        CompanionTheme(id: "Belle", displayName: "Belle", description: "Golden bee", folders: standardFolders),
        CompanionTheme(id: "Peaches", displayName: "Peaches", description: "Cream bunny", folders: standardFolders),
        CompanionTheme(id: "Nova", displayName: "Nova", description: "Lavender baby dragon", folders: standardFolders)
    ]

    // Keep the complete catalog available for asset validation and future
    // releases, while exposing only the currently supported choices in the UI.
    static let available: [CompanionTheme] = all.filter { ["Yuki", "Peaches"].contains($0.id) }

    static func isAvailable(_ id: String) -> Bool {
        available.contains { $0.id == id }
    }

    static func resolve(_ id: String) -> CompanionTheme { available.first { $0.id == id } ?? available[0] }
}
