import Foundation
import MarketKit

enum NftV2TransferType: String, Codable, Hashable {
    case eip721
    case eip1155
    case unknown
}

enum NftV2Chain: String, CaseIterable, Identifiable {
    case binanceSmartChain
    case ethereum
    case polygon
    case arbitrum
    case optimism
    case base

    var id: String {
        rawValue
    }

    var blockchainType: BlockchainType {
        switch self {
        case .ethereum: return .ethereum
        case .polygon: return .polygon
        case .arbitrum: return .arbitrumOne
        case .optimism: return .optimism
        case .base: return .base
        case .binanceSmartChain: return .binanceSmartChain
        }
    }

    var title: String {
        switch self {
        case .ethereum: return "nft_v2.chain.ethereum".localized
        case .polygon: return "nft_v2.chain.polygon".localized
        case .arbitrum: return "nft_v2.chain.arbitrum".localized
        case .optimism: return "nft_v2.chain.optimism".localized
        case .base: return "nft_v2.chain.base".localized
        case .binanceSmartChain: return "nft_v2.chain.bsc".localized
        }
    }

    var sortIndex: Int {
        switch self {
        case .ethereum: return 0
        case .polygon: return 1
        case .arbitrum: return 2
        case .optimism: return 3
        case .base: return 4
        case .binanceSmartChain: return 5
        }
    }
}

enum NftV2Market: String, CaseIterable, Identifiable {
    case openSea
    case element

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openSea: return "nft_v2.market.opensea".localized
        case .element: return "nft_v2.market.element".localized
        }
    }
}

struct NftV2Snapshot {
    let collections: [NftV2Collection]
    let chainStates: [NftV2ChainState]
}

struct NftV2ChainUpdate {
    let chainState: NftV2ChainState
    let collections: [NftV2Collection]
}

struct NftV2ProviderUpdate {
    let chain: NftV2Chain
    let accountId: String
    let address: String
}

struct NftV2ChainState: Identifiable {
    enum Status: Equatable {
        case inactive
        case cached(count: Int)
        case syncing(count: Int)
        case synced(count: Int)
        case unavailable(reason: String)
        case failed(message: String)
    }

    let chain: NftV2Chain
    let address: String?
    let market: NftV2Market?
    let status: Status
    let isRefreshing: Bool
    var payload: NftV2InventoryPayload?

    init(
        chain: NftV2Chain,
        address: String?,
        market: NftV2Market?,
        status: Status,
        isRefreshing: Bool = false,
        payload: NftV2InventoryPayload? = nil
    ) {
        self.chain = chain
        self.address = address
        self.market = market
        self.status = status
        self.isRefreshing = isRefreshing
        self.payload = payload
    }

    var id: String {
        chain.rawValue
    }

    var badgeText: String {
        switch status {
        case .inactive:
            return "nft_v2.state.inactive".localized
        case let .cached(count):
            return count == 0 ? "nft_v2.state.cached".localized : "nft_v2.state.items_count".localized(count)
        case let .syncing(count):
            return count == 0 ? "nft_v2.state.syncing".localized : "nft_v2.state.items_count".localized(count)
        case let .synced(count):
            return count == 0 ? "" : "nft_v2.state.items_count".localized(count)
        case .unavailable:
            return "nft_v2.state.pending".localized
        case .failed:
            return "nft_v2.state.error".localized
        }
    }

    var isSyncing: Bool {
        isRefreshing
    }

    var detailText: String {
        switch status {
        case .inactive:
            return "nft_v2.detail.inactive".localized
        case let .cached(count):
            return count == 0 ? "nft_v2.detail.cached_empty".localized : "nft_v2.detail.cached".localized
        case let .syncing(count):
            return count == 0 ? "nft_v2.detail.syncing_empty".localized : "nft_v2.detail.syncing".localized
        case let .synced(count):
            return count == 0 ? "nft_v2.detail.ready".localized : "nft_v2.detail.loaded".localized
        case let .unavailable(reason):
            return reason
        case let .failed(message):
            return message
        }
    }

    var isActionEnabled: Bool {
        switch status {
        case .cached, .syncing, .synced:
            return true
        default:
            return false
        }
    }
}

struct NftV2Collection: Identifiable, Hashable {
    let id: String
    let chain: NftV2Chain
    let contractAddress: String
    let name: String
    let imageUrl: String?
    let market: NftV2Market?
    let marketUrl: String?
    let items: [NftV2Asset]

    var count: Int {
        items.reduce(0) { $0 + $1.balance }
    }
}

struct NftV2Asset: Identifiable, Hashable {
    let id: String
    let nftUid: NftUid
    let chain: NftV2Chain
    let contractAddress: String
    let tokenId: String
    let standard: String
    let name: String
    let imageUrl: String?
    let collectionName: String
    let market: NftV2Market?
    let marketUrl: String?
    let balance: Int
    let canSend: Bool
    let transferType: NftV2TransferType
}

struct NftV2PendingTransferItem: Identifiable, Hashable {
    let id: String
    let chain: NftV2Chain
    let collectionId: String
    let collectionName: String
    let asset: NftV2Asset
    let amount: Int
    let transactionHash: String
    let explorerUrl: String?
    let submittedAt: Date
}

enum NftV2SendCapability: Equatable {
    enum BlockReason: Equatable {
        case syncing
        case unavailable
    }

    case checking
    case ready
    case blocked(reason: BlockReason)

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }
}
