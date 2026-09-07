import XCTest
@testable import EffyWoWCompanion

final class ThemeCatalogTests: XCTestCase {
    func testAllRequestedThemesAreAvailable() {
        XCTAssertEqual(Set(CompanionTheme.all.map(\.id)), ["Yuki", "Mochi", "Pippin", "Belle", "Peaches", "Nova"])
        XCTAssertEqual(CompanionTheme.all.count, 6)
    }

    func testEveryThemeUsesTheCompleteAnimationContract() {
        let expected = Set(["idle", "blink", "click", "hover", "thinking", "replying", "answerStart", "answerComplete", "look", "error", "rareIdleA", "rareIdleB"])
        for theme in CompanionTheme.all { XCTAssertEqual(Set(theme.folders.keys), expected) }
    }

    func testOnlyYukiAndBetaPeachesAreUserAccessible() {
        XCTAssertEqual(CompanionTheme.available.map(\.id), ["Yuki", "Peaches"])
        XCTAssertEqual(CompanionTheme.available.first { $0.id == "Peaches" }?.menuLabel, "Peaches — BETA · Cream bunny")
        XCTAssertFalse(CompanionTheme.isAvailable("Belle"))
    }
}
