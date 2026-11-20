import EvmKit
import Foundation
import MarketKit

extension AppConfig {
    // Shared with the app entitlements; independent of development bundle IDs.
    static let appGroupIdentifier = "group.com.anwang4.safewallet"

    static let backupSalt = "SafeWallet"

    static let analyticsLink = "https://unstoppable.money/analytics"

    static var spamCoinValueLimits: [String: Decimal] = [
        "XLM": 0.01,
        "USDT": 0.01,
        "USDC": 0.01,
        "USDD": 0.01,
        "DAI": 0.01,
        "BUSD": 0.01,
        "EURS": 0.01,
        "BSC-USD": 0.01,
    ]

    static var showTestSwitchers: Bool {
        AppEnvironment.config.showDevTools
    }

    static var blockchairApiKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "BlockchairApiKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func solanaAlchemyApiKeys(from value: String?) -> [String] {
        (value ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static var oneInchApiKey: String? {
        apiKey(.oneInch) ?? (Bundle.main.object(forInfoDictionaryKey: "OneInchApiKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var oneInchCommissionAddress: String? {
        (Bundle.main.object(forInfoDictionaryKey: "OneInchCommissionAddress") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var oneInchCommission: Decimal? {
        (Bundle.main.object(forInfoDictionaryKey: "OneInchCommission") as? String).flatMap {
            $0.isEmpty ? nil : Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    static var thorchainAffiliate: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ThorchainAffiliate") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var thorchainAffiliateBps: Int? {
        (Bundle.main.object(forInfoDictionaryKey: "ThorchainAffiliateBps") as? String).flatMap { $0.isEmpty ? nil : Int($0) }
    }

    static var mayaAffiliate: String? {
        (Bundle.main.object(forInfoDictionaryKey: "MayaAffiliate") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var mayaAffiliateBps: Int? {
        (Bundle.main.object(forInfoDictionaryKey: "MayaAffiliateBps") as? String).flatMap { $0.isEmpty ? nil : Int($0) }
    }

    static var isSafe4TestNet = false

    static func apiKeys(_ name: ApiKeyName) -> [String]? {
        ApiKeyManager.apiKeys(name: name)
    }

    static func apiKey(_ name: ApiKeyName) -> String? {
        ApiKeyManager.apiKeys(name: name)?.randomElement()
    }

    static var safe4ApiUrl: String {
        isSafe4TestNet == true ? "https://safe4testnet.anwang.com/api" : "https://safe4.anwang.com/api"
    }
}

extension Chain {
    static func safeFourChain() -> Chain {
        if AppConfig.isSafe4TestNet {
            return Chain.SafeFourTestNet
        }else {
            return Chain.SafeFour
        }
    }
}
