import XCTest

@testable import WalletCore

final class RestoreMnemonicServiceTests: XCTestCase {
    private let bip39Words = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about",
    ]

    private let moneroWords = [
        "abbey", "abducts", "ability", "ablaze", "abnormal", "abort",
        "abrasive", "absorb", "abyss", "academy", "aces", "aching",
        "acidic", "acoustic", "acquire", "across", "actress", "acumen",
        "adapt", "addicted", "adept", "adhesive", "adjust", "adopt",
        "abnormal",
    ]

    func testAccountTypeResolvesValidBip39Mnemonic() throws {
        let service = makeService()

        let accountType = try service.accountType(words: bip39Words)

        guard case let .mnemonic(words, salt, bip39Compliant) = accountType else {
            return XCTFail("Expected a BIP39 mnemonic account type")
        }

        XCTAssertEqual(words, bip39Words)
        XCTAssertEqual(salt, "")
        XCTAssertTrue(bip39Compliant)
    }

    func testAccountTypeRequiresPassphraseWhenEnabled() {
        let service = makeService()
        service.set(passphraseEnabled: true)

        XCTAssertThrowsError(try service.accountType(words: bip39Words)) { error in
            XCTAssertTrue(self.contains(error, .emptyPassphrase))
        }
    }

    func testAccountTypeResolvesValidMoneroMnemonic() throws {
        let service = makeService(supportsMonero: true)

        let accountType = try service.accountType(words: moneroWords)

        guard case let .moneroMnemonic(words, passphrase) = accountType else {
            return XCTFail("Expected a Monero mnemonic account type")
        }

        XCTAssertEqual(words, moneroWords)
        XCTAssertEqual(passphrase, "")
    }

    func testAccountTypeRejectsInvalidMoneroChecksum() {
        let service = makeService(supportsMonero: true)
        var invalidWords = moneroWords
        invalidWords[invalidWords.count - 1] = "abbey"

        XCTAssertThrowsError(try service.accountType(words: invalidWords)) { error in
            XCTAssertTrue(self.contains(error, .invalidMoneroChecksum))
        }
    }

    func testAccountTypeDoesNotTreatTwentyFiveBip39WordsAsBip39Mnemonic() {
        let service = makeService(supportsMonero: true)

        XCTAssertThrowsError(try service.accountType(words: bip39Words + bip39Words + [bip39Words[0]])) { error in
            XCTAssertTrue(self.contains(error, .invalidMoneroChecksum))
        }
    }

    func testAccountTypeRejectsMoneroMnemonicWhenMoneroSupportIsDisabled() {
        let service = makeService()

        XCTAssertThrowsError(try service.accountType(words: moneroWords))
    }

    func testAccountTypeRejectsWhitespaceOnlyMoneroPassphrase() {
        let service = makeService(supportsMonero: true)
        service.set(passphraseEnabled: true)
        service.passphrase = " \n "

        XCTAssertThrowsError(try service.accountType(words: moneroWords)) { error in
            XCTAssertTrue(self.contains(error, .emptyPassphrase))
        }
    }

    func testAccountTypePreservesNonEmptyMoneroPassphrase() throws {
        let service = makeService(supportsMonero: true)
        service.set(passphraseEnabled: true)
        service.passphrase = "seed offset"

        let accountType = try service.accountType(words: moneroWords)

        guard case let .moneroMnemonic(_, passphrase) = accountType else {
            return XCTFail("Expected a Monero mnemonic account type")
        }

        XCTAssertEqual(passphrase, "seed offset")
    }

    private func makeService(supportsMonero: Bool = false) -> RestoreMnemonicService {
        RestoreMnemonicService(languageManager: LanguageManager(), supportsMonero: supportsMonero)
    }

    private func contains(
        _ error: Error,
        _ expected: RestoreMnemonicService.RestoreError
    ) -> Bool {
        guard case let RestoreMnemonicService.ErrorList.errors(errors) = error else {
            return false
        }

        return errors.contains { error in
            switch (error, expected) {
            case (RestoreMnemonicService.RestoreError.emptyPassphrase, .emptyPassphrase),
                 (RestoreMnemonicService.RestoreError.invalidMoneroChecksum, .invalidMoneroChecksum):
                return true
            default:
                return false
            }
        }
    }
}
