import XCTest
@testable import WalletCore

final class Safe4NetworkSessionTests: XCTestCase {
    func testSwitchInvalidatesSessionBeforeCompletion() throws {
        let center = NotificationCenter()
        let session = Safe4NetworkSession(notificationCenter: center)
        XCTAssertNoThrow(try session.check())
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        XCTAssertFalse(session.isValid)
        XCTAssertThrowsError(try session.check()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testOldSessionStaysInvalidWhenNewSessionIsCreated() {
        let center = NotificationCenter()
        let old = Safe4NetworkSession(notificationCenter: center)
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        let new = Safe4NetworkSession(notificationCenter: center)
        XCTAssertFalse(old.isValid)
        XCTAssertTrue(new.isValid)
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        XCTAssertFalse(old.isValid)
        XCTAssertFalse(new.isValid)
    }

    func testCancellationRunsOnceAndSeesInvalidState() {
        let center = NotificationCenter()
        var count = 0
        var session: Safe4NetworkSession?
        session = Safe4NetworkSession(notificationCenter: center) {
            count += 1
            XCTAssertFalse(session!.isValid)
        }
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        XCTAssertEqual(count, 1)
        session = nil
    }

    func testUnrelatedNotificationDoesNotCancelSession() {
        let center = NotificationCenter()
        let session = Safe4NetworkSession(notificationCenter: center)
        center.post(name: Notification.Name("Unrelated"), object: nil)
        XCTAssertTrue(session.isValid)
    }

    func testReleasedSessionRemovesObserver() {
        let center = NotificationCenter()
        var count = 0
        var session: Safe4NetworkSession? = Safe4NetworkSession(notificationCenter: center) { count += 1 }
        weak var weakSession = session
        session = nil
        XCTAssertNil(weakSession)
        center.post(name: .safe4NetworkWillSwitch, object: nil)
        XCTAssertEqual(count, 0)
    }
}
