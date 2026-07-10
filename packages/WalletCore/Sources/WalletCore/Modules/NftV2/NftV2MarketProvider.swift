import Foundation

final class NftV2MarketProvider {
    func primaryMarket(chain: NftV2Chain) -> NftV2Market? {
        switch chain {
        case .ethereum, .polygon, .arbitrum, .optimism, .base:
            return .openSea
        case .binanceSmartChain:
            return .element
        }
    }

    func collectionUrl(chain: NftV2Chain, providerUid: String) -> String? {
        switch primaryMarket(chain: chain) {
        case .openSea:
            return "https://opensea.io/collection/\(providerUid)"
        case .element:
            return "https://element.market/collections/\(providerUid)"
        case nil:
            return nil
        }
    }

    func assetUrl(chain: NftV2Chain, contractAddress: String, tokenId: String) -> String? {
        switch primaryMarket(chain: chain) {
        case .openSea:
            return "https://opensea.io/assets/\(chain.openSeaPathComponent)/\(contractAddress)/\(tokenId)"
        case .element:
            return "https://element.market/assets/\(chain.elementPathComponent)/\(contractAddress)/\(tokenId)"
        case nil:
            return nil
        }
    }
}

private extension NftV2Chain {
    var openSeaPathComponent: String {
        switch self {
        case .ethereum: return "ethereum"
        case .polygon: return "matic"
        case .arbitrum: return "arbitrum"
        case .optimism: return "optimism"
        case .base: return "base"
        case .binanceSmartChain: return "bnb"
        }
    }

    var elementPathComponent: String {
        switch self {
        case .ethereum: return "eth"
        case .polygon: return "polygon"
        case .arbitrum: return "arbitrum"
        case .optimism: return "optimism"
        case .base: return "base"
        case .binanceSmartChain: return "bsc"
        }
    }
}
