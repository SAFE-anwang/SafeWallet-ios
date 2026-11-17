import UIKit
import XCTest
import WalletCore
@testable import Unstoppable

final class UnitTestHostTests: XCTestCase {
    @MainActor
    func testRunningHostHasNoWalletCoreOrWalletSceneDelegate() throws {
        // Check the actual launched host after UIKit has connected its scene, not a mock delegate.
        XCTAssertTrue(AppDelegate.isUnitTestHost, "Run this suite with Development's unit-test Test action")
        XCTAssertFalse(UIApplication.shared.connectedScenes.isEmpty)
        for scene in UIApplication.shared.connectedScenes {
            XCTAssertFalse(scene.delegate is AppSceneDelegate)
        }
        XCTAssertNil(Core.instance, "Pure unit tests must not start real wallets before XCTest exits")
    }
}
