import XCTest
@testable import EffyWoWCompanion

final class CursorContextTests: XCTestCase {
    func testTopLeftCoordinatesUseQuartzWindowOrigin() {
        let c = CursorContext(global: CGPoint(x: 100, y: 600), window: CGRect(x: 100, y: 100, width: 800, height: 500))
        XCTAssertEqual(c.normalizedX, 0); XCTAssertEqual(c.normalizedY, 0); XCTAssertTrue(c.isInside)
    }
    func testBottomRightCoordinates() {
        let c = CursorContext(global: CGPoint(x: 900, y: 100), window: CGRect(x: 100, y: 100, width: 800, height: 500))
        XCTAssertEqual(c.normalizedX, 1); XCTAssertEqual(c.normalizedY, 1); XCTAssertTrue(c.isInside)
    }
    func testOutsideWindowIsSafe() { XCTAssertFalse(CursorContext(global: CGPoint(x: 0, y: 0), window: CGRect(x: 100, y: 100, width: 800, height: 500)).isInside) }
    func testDeicticDetector() { XCTAssertTrue(DeicticQuestionDetector.needsContext("girl what’s this 😭")); XCTAssertFalse(DeicticQuestionDetector.needsContext("what level is X?")) }
}
