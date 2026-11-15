import XCTest
@testable import WalletCore

final class MarketApiConfigurationTests: XCTestCase {
    func testMissingOrInvalidOverrideUsesEnvironmentDefault() {
        for value: String? in [nil, "", " \n", "$(MARKET_API_URL)", "${MARKET_API_URL}", "https:", "/v1/coins"] {
            XCTAssertEqual(AppEnvironment.marketApiUrl(override: value), AppEnvironment.config.marketApiUrl)
        }
    }

    func testValidOverrideIsPreserved() {
        XCTAssertEqual(AppEnvironment.marketApiUrl(override: " https://example.com/api "), "https://example.com/api")
    }
}
