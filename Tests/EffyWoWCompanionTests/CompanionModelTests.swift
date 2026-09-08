import XCTest
@testable import EffyWoWCompanion

@MainActor
final class CompanionModelTests: XCTestCase {
    private let transcriptKey = "yuki.messages"

    func testOutgoingMessageLifecycleIsUpdatedInPlace() {
        UserDefaults.standard.removeObject(forKey: transcriptKey)
        let model = CompanionModel()
        let id = model.enqueueUser("hello")

        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages[0].id, id)
        XCTAssertEqual(model.messages[0].deliveryState, .queued)

        model.updateDelivery(id, .submitted)
        XCTAssertEqual(model.messages[0].deliveryState, .submitted)
    }

    func testStreamingResponseUsesOneBubbleAndFinalizesWithoutDuplication() {
        UserDefaults.standard.removeObject(forKey: transcriptKey)
        let model = CompanionModel()
        let id = model.enqueueUser("hello")

        model.updateStreamingResponse(for: id, text: "Hi")
        model.updateStreamingResponse(for: id, text: "Hi there")
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[1].text, "Hi there")
        XCTAssertEqual(model.messages[1].deliveryState, .responding)

        model.completeStreamingResponse(for: id, text: "Hi there!")
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[0].deliveryState, .completed)
        XCTAssertEqual(model.messages[1].text, "Hi there!")
        XCTAssertEqual(model.messages[1].deliveryState, .completed)
    }

    func testOlderTranscriptWithoutDeliveryStateStillDecodes() throws {
        let data = #"[{"id":"00000000-0000-0000-0000-000000000001","role":"user","text":"old message"}]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([YukiChatMessage].self, from: data)
        XCTAssertEqual(decoded.first?.text, "old message")
        XCTAssertNil(decoded.first?.deliveryState)
    }

    func testRetryRestoresFailedMessageWithoutOverwritingANewDraft() {
        UserDefaults.standard.removeObject(forKey: transcriptKey)
        UserDefaults.standard.removeObject(forKey: "yuki.draft")
        let model = CompanionModel()
        let id = model.enqueueUser("try this again")
        model.updateDelivery(id, .failed)

        model.restoreDraft(from: id)
        XCTAssertEqual(model.draft, "try this again")

        model.draft = "new thought"
        model.restoreDraft(from: id)
        XCTAssertEqual(model.draft, "new thought")
    }
}
