import Foundation
import XCTest
@testable import WalletCore

final class ForkLocalizationTests: XCTestCase {
    func testCurrentLanguageThenEnglishThenKeyUsingAppResources() throws {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: "current_language")
        defer { defaults.set(stored, forKey: "current_language") }
        let manager = LanguageManager()
        for language in ["de", "es", "fr", "ko", "pt-BR", "ru", "tr"] {
            manager.currentLanguage = language
            let directory = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
            let table = try XCTUnwrap(Bundle(url: directory))
            XCTAssertEqual(manager.localize(string: "button.next", bundle: .main),
                           table.localizedString(forKey: "button.next", value: nil, table: nil), language)
            for (key, expected) in [
                ("create_wallet.advanced", "Advanced"), ("restore.passphrase", "Passphrase"),
                ("restore.non_standard_import", "Non-Standard Import"),
                ("nft_asset.save_to_photos.failed", "Failed to save the NFT image."),
                ("settings.personal_support.failed", "Request failed."),
            ] {
                XCTAssertEqual(manager.localize(string: key, bundle: .main), expected, language)
            }
            XCTAssertEqual(manager.localize(string: "review.missing.example", bundle: .main), "review.missing.example")
        }
        manager.currentLanguage = "zh"
        XCTAssertEqual(manager.localize(string: "create_wallet.advanced", bundle: .main), "高级")
    }
}
