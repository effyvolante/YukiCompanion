struct DeicticQuestionDetector {
    static let phrases = [
        "what's this", "what’s this", "what is this", "what's that", "what’s that", "what is that",
        "who's this", "who’s this", "who is this", "who's that", "who’s that", "who is that",
        "this guy", "that guy", "this person", "that person", "this npc", "that npc", "this object", "that object",
        "this item", "that item", "this quest", "that quest", "this icon", "that icon",
        "what am i looking at", "what am i hovering", "what's over there", "what’s over there", "under my mouse",
        "why can't i click this", "why can’t i click this", "where is this", "look at this", "look at that"
    ]

    static func needsContext(_ text: String) -> Bool {
        let s = text.lowercased().replacingOccurrences(of: "’", with: "'")
        if phrases.contains(where: s.contains) { return true }

        // Broad observational questions should default to a WoW screenshot.
        // This intentionally favors visual context over making the user repeat
        // a question when they are clearly asking about something on screen.
        let asksAboutVisibleThing = ["this", "that", "here", "there", "person", "guy", "npc", "object", "thing", "item", "icon", "mount", "quest", "doing", "next to me"]
        let asksAQuestion = ["what", "who", "where", "why", "which", "can you", "is ", "are "].contains(where: s.contains)
        return asksAQuestion && asksAboutVisibleThing.contains(where: s.contains)
    }
}
