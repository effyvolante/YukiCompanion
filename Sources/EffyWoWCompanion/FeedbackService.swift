import AppKit

enum FeedbackService {
    static let feedbackURL = URL(string: "https://github.com/effyvolante/YukiCompanion/issues/new?template=feedback.yml&title=Feedback%20from%20Yuki%20Companion")!

    static func openForm() {
        NSWorkspace.shared.open(feedbackURL)
    }
}
