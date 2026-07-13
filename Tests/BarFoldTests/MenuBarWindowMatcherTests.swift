import CoreGraphics
import XCTest
@testable import BarFold

final class MenuBarWindowMatcherTests: XCTestCase {
    func testMatchesNearbyWindowByFrame() {
        let candidate = MenuBarWindowMatchCandidate(
            frame: CGRect(x: 100, y: 0, width: 24, height: 30),
            expectedTitles: []
        )
        let window = windowRecord(id: 10, x: 102, title: nil)

        XCTAssertEqual(
            MenuBarWindowMatcher.match(candidates: [candidate], availableWindows: [window]).first??.id,
            10
        )
    }

    func testMatchesOffscreenWindowByExactBundleTitle() {
        let candidate = MenuBarWindowMatchCandidate(
            frame: CGRect(x: 7, y: 980, width: 24, height: 26),
            expectedTitles: ["com.example.menu"]
        )
        let window = windowRecord(id: 11, x: 400, title: "com.example.menu")

        XCTAssertEqual(
            MenuBarWindowMatcher.match(candidates: [candidate], availableWindows: [window]).first??.id,
            11
        )
    }

    func testDoesNotMatchAccessibilityCandidateWithoutRealWindow() {
        let candidate = MenuBarWindowMatchCandidate(
            frame: CGRect(x: 7, y: 980, width: 24, height: 26),
            expectedTitles: ["com.example.missing"]
        )
        let unrelatedWindow = windowRecord(id: 12, x: 400, title: "com.example.other")

        XCTAssertNil(
            MenuBarWindowMatcher.match(
                candidates: [candidate],
                availableWindows: [unrelatedWindow]
            ).first!
        )
    }

    func testDoesNotReuseAWindowForTwoCandidates() {
        let candidates = [
            MenuBarWindowMatchCandidate(
                frame: CGRect(x: 100, y: 0, width: 24, height: 30),
                expectedTitles: []
            ),
            MenuBarWindowMatchCandidate(
                frame: CGRect(x: 101, y: 0, width: 24, height: 30),
                expectedTitles: []
            )
        ]

        let matches = MenuBarWindowMatcher.match(
            candidates: candidates,
            availableWindows: [windowRecord(id: 13, x: 100, title: nil)]
        )

        XCTAssertEqual(matches.first??.id, 13)
        XCTAssertNil(matches.last!)
    }

    private func windowRecord(
        id: CGWindowID,
        x: CGFloat,
        title: String?
    ) -> MenuBarWindowBridge.WindowRecord {
        MenuBarWindowBridge.WindowRecord(
            id: id,
            ownerPID: 100,
            frame: CGRect(x: x, y: 0, width: 24, height: 30),
            title: title
        )
    }
}
