import XCTest

@testable import WalletCore

final class WalletItemDerivationTests: XCTestCase {
    func testMnemonicDerivationUsesPathPurpose() {
        XCTAssertEqual(WalletItem.mnemonicDerivation(path: "m/44'/0'/1'"), .bip44)
        XCTAssertEqual(WalletItem.mnemonicDerivation(path: "m/49'/0'/0'"), .bip49)
        XCTAssertEqual(WalletItem.mnemonicDerivation(path: "m/84'/0'/0'/0/0"), .bip84)
        XCTAssertEqual(WalletItem.mnemonicDerivation(path: "m/86'/0'/0'"), .bip86)
    }

    func testMnemonicDerivationRejectsUnsupportedPath() {
        XCTAssertNil(WalletItem.mnemonicDerivation(path: "m/60'/0'/0'"))
        XCTAssertNil(WalletItem.mnemonicDerivation(path: "not-a-derivation-path"))
    }
}
