import XCTest
@testable import BarFold

final class PlacementDiscoveryTrackerTests: XCTestCase {
    func testFirstScanMarksEveryItemAsChanged() {
        var tracker = PlacementDiscoveryTracker()

        XCTAssertEqual(
            tracker.changedIDs(in: ["chat": 100, "meeting": 200]),
            ["chat", "meeting"]
        )
    }

    func testStableProcessDoesNotTriggerRepeatedSynchronization() {
        var tracker = PlacementDiscoveryTracker()
        _ = tracker.changedIDs(in: ["chat": 100])

        XCTAssertTrue(tracker.changedIDs(in: ["chat": 100]).isEmpty)
    }

    func testPIDChangeMarksRestartedItemAsChanged() {
        var tracker = PlacementDiscoveryTracker()
        _ = tracker.changedIDs(in: ["chat": 100, "meeting": 200])

        XCTAssertEqual(
            tracker.changedIDs(in: ["chat": 101, "meeting": 200]),
            ["chat"]
        )
    }

    func testSingleMissingScanDoesNotTreatItemAsRestarted() {
        var tracker = PlacementDiscoveryTracker()
        _ = tracker.changedIDs(in: ["chat": 100])
        XCTAssertTrue(tracker.changedIDs(in: [:]).isEmpty)

        XCTAssertTrue(tracker.changedIDs(in: ["chat": 100]).isEmpty)
    }

    func testItemIsChangedAfterTwoMissingScansAndReturn() {
        var tracker = PlacementDiscoveryTracker()
        _ = tracker.changedIDs(in: ["chat": 100])
        XCTAssertTrue(tracker.changedIDs(in: [:]).isEmpty)
        XCTAssertTrue(tracker.changedIDs(in: [:]).isEmpty)

        XCTAssertEqual(tracker.changedIDs(in: ["chat": 100]), ["chat"])
    }

    func testResetMarksExistingItemsAsChangedAgain() {
        var tracker = PlacementDiscoveryTracker()
        _ = tracker.changedIDs(in: ["chat": 100])
        tracker.reset()

        XCTAssertEqual(tracker.changedIDs(in: ["chat": 100]), ["chat"])
    }
}
