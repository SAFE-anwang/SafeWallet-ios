import Foundation
import MarketKit
import RxRelay
import RxSwift
import SolanaKit

public class SolanaRpcSourceManager {
    private let blockchainSettingsStorage: BlockchainSettingsStorage
    private let marketKit: MarketKit.Kit
    private let disposeBag = DisposeBag()

    private let rpcSourceRelay = PublishRelay<Void>()

    public init(blockchainSettingsStorage: BlockchainSettingsStorage, marketKit: MarketKit.Kit) {
        self.blockchainSettingsStorage = blockchainSettingsStorage
        self.marketKit = marketKit

        ApiKeyManager.rpcEndpointsUpdatedObservable
            .filter { changes in changes.contains { $0.network == .sol } }
            .subscribe(onNext: { [weak self] _ in
                self?.rpcSourceRelay.accept(())
            })
            .disposed(by: disposeBag)
    }

    var allRpcSources: [SolanaKit.RpcSource] {
        var sources = [SolanaKit.RpcSource]()
        if let endpoint = ApiKeyManager.rpcEndpointConfig(network: .sol),
           let remoteSource = Self.remoteRpcSource(network: endpoint.network, endpoint: endpoint.endpoint)
        {
            sources.append(remoteSource)
        }

        let apiKeys = AppConfig.solanaAlchemyApiKeys
        if !apiKeys.isEmpty {
            sources.append(.alchemy(apiKeys: apiKeys))
        }
        sources.append(.mainnetBeta())
        return sources
    }

    var rpcSource: SolanaKit.RpcSource {
        let savedName = blockchainSettingsStorage.evmSyncSourceUrl(blockchainType: .solana)
        return allRpcSources.first { $0.name == savedName } ?? allRpcSources[0]
    }

    func save(rpcSource: SolanaKit.RpcSource) {
        blockchainSettingsStorage.save(evmSyncSourceUrl: rpcSource.name, blockchainType: .solana)
        rpcSourceRelay.accept(())
    }

    var rpcSourceObservable: Observable<Void> {
        rpcSourceRelay.asObservable()
    }

    var blockchain: Blockchain? {
        try? marketKit.blockchain(uid: BlockchainType.solana.uid)
    }

    static func remoteRpcSource(network: String, endpoint: String) -> SolanaKit.RpcSource? {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard network == RpcNetworkName.sol.rawValue,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url
        else {
            return nil
        }

        return SolanaKit.RpcSource(name: "Remote Solana RPC", url: url, network: .mainnetBeta)
    }
}
