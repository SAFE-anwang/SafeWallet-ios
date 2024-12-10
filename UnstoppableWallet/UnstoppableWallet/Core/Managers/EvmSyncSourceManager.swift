import EvmKit
import Foundation
import MarketKit
import RxRelay
import RxSwift

class EvmSyncSourceManager {
    private let testNetManager: TestNetManager
    private let blockchainSettingsStorage: BlockchainSettingsStorage
    private let evmSyncSourceStorage: EvmSyncSourceStorage

    private let syncSourceRelay = PublishRelay<BlockchainType>()
    private let syncSourcesUpdatedRelay = PublishRelay<BlockchainType>()

    init(testNetManager: TestNetManager, blockchainSettingsStorage: BlockchainSettingsStorage, evmSyncSourceStorage: EvmSyncSourceStorage) {
        self.testNetManager = testNetManager
        self.blockchainSettingsStorage = blockchainSettingsStorage
        self.evmSyncSourceStorage = evmSyncSourceStorage
    }

    private func defaultTransactionSource(blockchainType: BlockchainType) -> EvmKit.TransactionSource {
        switch blockchainType {
        case .ethereum: return .ethereumEtherscan(apiKeys: [AppConfig.etherscanKey])
        case .binanceSmartChain: return .bscscan(apiKeys: [AppConfig.bscscanKey])
        case .polygon: return .polygonscan(apiKeys: AppConfig.polygonscanKeys)
        case .avalanche: return .snowtrace(apiKeys: [AppConfig.snowtraceKey])
        case .optimism: return .optimisticEtherscan(apiKeys: [AppConfig.optimismEtherscanKey])
        case .arbitrumOne: return .arbiscan(apiKeys: [AppConfig.arbiscanKey])
        case .gnosis: return .gnosis(apiKeys: [AppConfig.gnosisscanKey])
        case .fantom: return .fantom(apiKeys: [AppConfig.ftmscanKey])
        case .safe4: return .safeFourscanTestNet(apiKeys: [AppConfig.etherscanKey])
        default: fatalError("Non-supported EVM blockchain")
        }
    }
}

extension RpcSource {
    
    static func safeEthereumRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://ethereum-mainnet.core.chainstack.com/a1911ee247f4f8de22c1f4e55865f616")!], auth: nil)
    }
    
    static func safeSolanaRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://solana-mainnet.core.chainstack.com/254981cd2d169be592ee9604c7d47446")!], auth: nil)
    }
    
    static func safeBscRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://bsc-mainnet.core.chainstack.com/67f0d109c5c0b7f0aa251a89f12c0b7b")!], auth: nil)
    }
    
    static func safeBscRpcHttp2() -> RpcSource {
        .http(urls: [URL(string: "https://nd-981-064-010.p2pify.com/3abdd3b90f012f4427380b632deb4180")!], auth: nil)
    }

    static func safePolygonRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://polygon-mainnet.core.chainstack.com/e9c77e1e564c041e111132211eb0df0f")!], auth: nil)
    }
    
    static func safeAvaxNetworkHttp() -> RpcSource {
        .http(urls: [URL(string: "https://avalanche-mainnet.core.chainstack.com/ext/bc/C/rpc/0d78d62f3dc1baf5968e7bf78018ce02")!], auth: nil)
    }
    
    static func safeOptimismRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://optimism-mainnet.core.chainstack.com/9f3d2000dae7846908ac871ef96e18fe")!], auth: nil)
    }
    
    static func safeArbitrumOneRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://arbitrum-mainnet.core.chainstack.com/43d06a32450091e3da629e17f3d53a5e")!], auth: nil)
    }
    
    static func safeGnosisRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://nd-786-294-051.p2pify.com/4c89e746f92af4af9f76befc8dd64e59")!], auth: nil)
    }
    
    static func safeFantomRpcHttp() -> RpcSource {
        .http(urls: [URL(string: "https://fantom-mainnet.core.chainstack.com/01d412d3dbe245ad17742e58fa017171")!], auth: nil)
    }
}

extension EvmSyncSourceManager {
    
    var syncSourceObservable: Observable<BlockchainType> {
        syncSourceRelay.asObservable()
    }

    var syncSourcesUpdatedObservable: Observable<BlockchainType> {
        syncSourcesUpdatedRelay.asObservable()
    }

    func defaultSyncSources(blockchainType: BlockchainType) -> [EvmSyncSource] {
        switch blockchainType {
        case .ethereum:
            if testNetManager.testNetEnabled {
                return [
//                    EvmSyncSource(
//                        name: "BlocksDecoded Sepolia",
//                        rpcSource: .http(urls: [URL(string: "\(AppConfig.marketApiUrl)/v1/ethereum-rpc/sepolia")!], auth: nil),
//                        transactionSource: EvmKit.TransactionSource(
//                            name: "sepolia.etherscan.io",
//                            type: .etherscan(apiBaseUrl: "https://api-sepolia.etherscan.io", txBaseUrl: "https://sepiloa.etherscan.io", apiKey: AppConfig.etherscanKey)
//                        )
//                    ),
                    EvmSyncSource(
                        name: "Infura Sepolia",
                        rpcSource: .http(urls: [URL(string: "https://sepolia.infura.io/v3/\(AppConfig.infuraCredentials.id)")!], auth: AppConfig.infuraCredentials.secret),
                        transactionSource: EvmKit.TransactionSource(
                            name: "sepolia.etherscan.io",
                            type: .etherscan(apiBaseUrl: "https://api-sepolia.etherscan.io", txBaseUrl: "https://sepiloa.etherscan.io", apiKeys: [AppConfig.etherscanKey])
                        )
                    ),
                ]
            } else {
                return [
//                    EvmSyncSource(
//                        name: "BlocksDecoded",
//                        rpcSource: .http(urls: [URL(string: "\(AppConfig.marketApiUrl)/v1/ethereum-rpc/mainnet")!], auth: nil),
//                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
//                    ),
                    EvmSyncSource(
                        name: "ETH RPC",
                        rpcSource: .safeEthereumRpcHttp(),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
                    EvmSyncSource(
                        name: "Infura",
                        rpcSource: .ethereumInfuraWebsocket(projectId: AppConfig.infuraCredentials.id, projectSecret: AppConfig.infuraCredentials.secret),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
                    EvmSyncSource(
                        name: "Infura",
                        rpcSource: .ethereumInfuraHttp(projectId: AppConfig.infuraCredentials.id, projectSecret: AppConfig.infuraCredentials.secret),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
                    EvmSyncSource(
                        name: "LlamaNodes",
                        rpcSource: .http(urls: [URL(string: "https://eth.llamarpc.com")!], auth: nil),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
                ]
            }
        case .binanceSmartChain:
            if testNetManager.testNetEnabled {
                return [
                    EvmSyncSource(
                        name: "Binance TestNet",
                        rpcSource: .http(urls: [URL(string: "https://data-seed-prebsc-1-s1.binance.org:8545")!], auth: nil),
                        transactionSource: EvmKit.TransactionSource(
                            name: "testnet.bscscan.com",
                            type: .etherscan(apiBaseUrl: "https://api-testnet.bscscan.com", txBaseUrl: "https://testnet.bscscan.com", apiKeys: [AppConfig.bscscanKey])
                        )
                    ),
                ]
            } else {
                return [
//                    EvmSyncSource(
//                        name: "Binance",
//                        rpcSource: .binanceSmartChainHttp(),
//                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
//                    ),
                    EvmSyncSource(
                        name: "BSC RPC",
                        rpcSource: .safeBscRpcHttp(),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
                    EvmSyncSource(
                        name: "BSC RPC",
                        rpcSource: .safeBscRpcHttp2(),
                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                    ),
//                    EvmSyncSource(
//                        name: "Omnia",
//                        rpcSource: .http(urls: [URL(string: "https://endpoints.omniatech.io/v1/bsc/mainnet/public")!], auth: nil),
//                        transactionSource: defaultTransactionSource(blockchainType: blockchainType)
//                    ),
                ]
            }
        case .polygon:
            return [
                EvmSyncSource(
                    name: "Polygon RPC",
                    rpcSource: .safePolygonRpcHttp(),//.polygonRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "LlamaNodes",
                    rpcSource: .http(urls: [URL(string: "https://polygon.llamarpc.com")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .avalanche:
            return [
                EvmSyncSource(
                    name: "Avax Network",
                    rpcSource: .safeAvaxNetworkHttp(),//.avaxNetworkHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "PublicNode",
                    rpcSource: .http(urls: [URL(string: "https://avalanche-evm.publicnode.com")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .optimism:
            return [
                EvmSyncSource(
                    name: "Optimism",
                    rpcSource: .safeOptimismRpcHttp(),//.optimismRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "Omnia",
                    rpcSource: .http(urls: [URL(string: "https://endpoints.omniatech.io/v1/op/mainnet/public")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .arbitrumOne:
            return [
                EvmSyncSource(
                    name: "Arbitrum",
                    rpcSource: .safeArbitrumOneRpcHttp(),//.arbitrumOneRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "Omnia",
                    rpcSource: .http(urls: [URL(string: "https://endpoints.omniatech.io/v1/arbitrum/one/public")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .gnosis:
            return [
                EvmSyncSource(
                    name: "Gnosis Chain",
                    rpcSource: .safeGnosisRpcHttp(),//.gnosisRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "Ankr",
                    rpcSource: .http(urls: [URL(string: "https://rpc.ankr.com/gnosis")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .fantom:
            return [
                EvmSyncSource(
                    name: "Fantom Chain",
                    rpcSource: .safeFantomRpcHttp(),//.fantomRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
                EvmSyncSource(
                    name: "Ankr",
                    rpcSource: .http(urls: [URL(string: "https://rpc.ankr.com/fantom")!], auth: nil),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                ),
            ]
        case .safe4:
            return [
                EvmSyncSource(
                    name: "SAFE4",
                    rpcSource: .safeFourTestNetRpcHttp(),
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                )
            ]
        default:
            return []
        }
    }

    func customSyncSources(blockchainType: BlockchainType?) -> [EvmSyncSource] {
        do {
            let records: [EvmSyncSourceRecord]
            if let blockchainType {
                records = try evmSyncSourceStorage.records(blockchainTypeUid: blockchainType.uid)
            } else {
                records = try evmSyncSourceStorage.getAll()
            }

            return records.compactMap { record in
                let blockchainType = BlockchainType(uid: record.blockchainTypeUid)
                guard let url = URL(string: record.url), let scheme = url.scheme else {
                    return nil
                }

                let rpcSource: RpcSource

                switch scheme {
                case "http", "https": rpcSource = .http(urls: [url], auth: record.auth)
                case "ws", "wss": rpcSource = .webSocket(url: url, auth: record.auth)
                default: return nil
                }

                return EvmSyncSource(
                    name: url.host ?? "",
                    rpcSource: rpcSource,
                    transactionSource: defaultTransactionSource(blockchainType: blockchainType)
                )
            }
        } catch {
            return []
        }
    }

    func allSyncSources(blockchainType: BlockchainType) -> [EvmSyncSource] {
        defaultSyncSources(blockchainType: blockchainType) + customSyncSources(blockchainType: blockchainType)
    }

    func syncSource(blockchainType: BlockchainType) -> EvmSyncSource {
        let syncSources = allSyncSources(blockchainType: blockchainType)

        if let urlString = blockchainSettingsStorage.evmSyncSourceUrl(blockchainType: blockchainType),
           let syncSource = syncSources.first(where: { $0.rpcSource.url.absoluteString == urlString })
        {
            return syncSource
        }

        return syncSources[0]
    }

    func httpSyncSource(blockchainType: BlockchainType) -> EvmSyncSource? {
        let syncSources = allSyncSources(blockchainType: blockchainType)

        if let urlString = blockchainSettingsStorage.evmSyncSourceUrl(blockchainType: blockchainType),
           let syncSource = syncSources.first(where: { $0.rpcSource.url.absoluteString == urlString }), syncSource.isHttp
        {
            return syncSource
        }

        return syncSources.first { $0.isHttp }
    }

    func saveCurrent(syncSource: EvmSyncSource, blockchainType: BlockchainType) {
        blockchainSettingsStorage.save(evmSyncSourceUrl: syncSource.rpcSource.url.absoluteString, blockchainType: blockchainType)
        syncSourceRelay.accept(blockchainType)
    }

    func saveSyncSource(blockchainType: BlockchainType, url: URL, auth: String?) {
        let record = EvmSyncSourceRecord(
            blockchainTypeUid: blockchainType.uid,
            url: url.absoluteString,
            auth: auth
        )

        try? evmSyncSourceStorage.save(record: record)

        if let syncSource = customSyncSources(blockchainType: blockchainType).first(where: { $0.rpcSource.url == url }) {
            saveCurrent(syncSource: syncSource, blockchainType: blockchainType)
        }

        syncSourcesUpdatedRelay.accept(blockchainType)
    }

    func delete(syncSource: EvmSyncSource, blockchainType: BlockchainType) {
        let isCurrent = self.syncSource(blockchainType: blockchainType) == syncSource

        try? evmSyncSourceStorage.delete(blockchainTypeUid: blockchainType.uid, url: syncSource.rpcSource.url.absoluteString)

        if isCurrent {
            syncSourceRelay.accept(blockchainType)
        }

        syncSourcesUpdatedRelay.accept(blockchainType)
    }
}

extension EvmSyncSourceManager {
    var customSources: [EvmSyncSourceRecord] {
        (try? evmSyncSourceStorage.getAll()) ?? []
    }

    var selectedSources: [SelectedSource] {
        EvmBlockchainManager
            .blockchainTypes
            .map { type in
                SelectedSource(
                    blockchainTypeUid: type.uid,
                    url: syncSource(blockchainType: type).rpcSource.url.absoluteString
                )
            }
    }
}

extension EvmSyncSourceManager {
    func decrypt(sources: [CustomSyncSource], passphrase: String) throws -> [EvmSyncSourceRecord] {
        try sources.map { source in
            let auth = try source.auth
                .flatMap { try $0.decrypt(passphrase: passphrase) }
                .flatMap { String(data: $0, encoding: .utf8) }

            return EvmSyncSourceRecord(
                blockchainTypeUid: source.blockchainTypeUid,
                url: source.url,
                auth: auth
            )
        }
    }

    func encrypt(sources: [EvmSyncSourceRecord], passphrase: String) throws -> [CustomSyncSource] {
        try sources.map { source in
            let crypto = try source.auth
                .flatMap { $0.isEmpty ? nil : $0 }
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try BackupCrypto.encrypt(data: $0, passphrase: passphrase) }

            return CustomSyncSource(
                blockchainTypeUid: source.blockchainTypeUid,
                url: source.url,
                auth: crypto
            )
        }
    }
}

extension EvmSyncSourceManager {
    func restore(selected: [SelectedSource], custom: [EvmSyncSourceRecord]) {
        var blockchainTypes = Set<BlockchainType>()
        custom.forEach { source in
            blockchainTypes.insert(BlockchainType(uid: source.blockchainTypeUid))
            try? evmSyncSourceStorage.save(record: source)
        }

        selected.forEach { source in
            let blockchainType = BlockchainType(uid: source.blockchainTypeUid)
            if let syncSource = allSyncSources(blockchainType: blockchainType)
                .first(where: { $0.rpcSource.url.absoluteString == source.url })
            {
                saveCurrent(syncSource: syncSource, blockchainType: blockchainType)
            }
        }

        blockchainTypes.forEach { blockchainType in
            syncSourcesUpdatedRelay.accept(blockchainType)
        }
    }
}

extension EvmSyncSourceManager {
    struct SelectedSource: Codable {
        let blockchainTypeUid: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case blockchainTypeUid = "blockchain_type_id"
            case url
        }
    }

    struct CustomSyncSource: Codable {
        let blockchainTypeUid: String
        let url: String
        let auth: BackupCrypto?

        enum CodingKeys: String, CodingKey {
            case blockchainTypeUid = "blockchain_type_id"
            case url
            case auth
        }
    }

    struct SyncSourceBackup: Codable {
        let selected: [SelectedSource]
        let custom: [CustomSyncSource]
    }
}

