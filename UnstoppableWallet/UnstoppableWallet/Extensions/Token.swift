import BigInt
import Foundation
import MarketKit

extension Token {

    var protocolName: String? {
        switch type {
        case .native:
            switch blockchainType {
            case .ethereum, .binanceSmartChain, .dogecoin,.tron: return nil
            case .binanceChain: return "BEP2"
            case .safe: return "SAFE3"
            case .safe4: return nil//"SAFE4"
            default: return blockchain.name
            }
        case .eip20:
            switch blockchainType {
            case .ethereum: return "ERC20"
            case .binanceSmartChain: return "BEP20"
            case .tron: return "TRC20"
            case .safe4: return "SRC20"
            default: return blockchain.name
            }
        case .bep2:
            return "BEP2"
        default:
            return blockchain.name
        }
    }

    var isCustom: Bool {
        coin.uid == tokenQuery.customCoinUid
    }

    var placeholderImageName: String {
        if [.safe, .safe4].contains(blockchainType) {
            "safe-anwang_trx_32"
        }else {
            "\(blockchainType.uid)_\(type.tokenProtocol)_32"
        }
    }

    var swappable: Bool {
        switch blockchainType {
        case .ethereum: return true
        case .binanceSmartChain: return true
        case .polygon: return coin.uid == safeCoinUid ? false : true
        case .avalanche: return true
        case .optimism: return true
        case .arbitrumOne: return true
        case .gnosis: return true
        case .fantom: return true
        case .safe4: return true
        default: return false
        }
    }

    var badge: String? {
        switch type {
        case let .derived(derivation): return derivation.mnemonicDerivation.rawValue.uppercased()
        case let .addressType(type): return type.bitcoinCashCoinType.title.uppercased()
        default: return protocolName?.uppercased()
        }
    }
    
    var fullBadge: String {
        (badge ?? "coin_platforms.native".localized).uppercased()
    }
}

extension Token: Comparable {
    public static func < (lhs: Token, rhs: Token) -> Bool {
        let lhsTypeOrder = lhs.type.order
        let rhsTypeOrder = rhs.type.order

        guard lhsTypeOrder == rhsTypeOrder else {
            return lhsTypeOrder < rhsTypeOrder
        }

        return lhs.blockchainType.order < rhs.blockchainType.order
    }
}

extension Token {
    func fractionalMonetaryValue(value: Decimal) -> BigUInt {
        BigUInt(value.hs.roundedString(decimal: decimals)) ?? 0
    }
}
