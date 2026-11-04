import MarketKit
import XCTest
@testable import WalletCore

final class CreateAccountDefaultWalletTests: XCTestCase {
    func testDefaultTokenQueriesIncludeSafeNativeToken() {
        XCTAssertTrue(
            CreateAccountViewModel.defaultTokenQueries.contains {
                $0.id == BlockchainType.safe4.defaultTokenQuery.id
            }
        )
    }
}
