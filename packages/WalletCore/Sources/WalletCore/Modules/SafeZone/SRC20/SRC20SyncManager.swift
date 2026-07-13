import HsToolKit
import Foundation

class SRC20SyncManager {
    private var service: SyncSafe4TokensService?

    init(wallet: Wallet, adapter: IAdapter) {
        guard wallet.coin.uid.isSafeCoin && wallet.token.blockchain.type == .safe4 &&  wallet.token.type == .native else { return }
        switch adapter {
        case let adapter as ISendEthereumAdapter:
            guard let privateKey = adapter.evmKitWrapper.signer?.privateKey else {
                return
            }
            let chainId = adapter.evmKitWrapper.evmKit.chain.id
            let provider = SyncSafe4TokensProvider(networkManager: Core.shared.networkManager, chainId: chainId)
            let service = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey, lockAddress: adapter.evmKitWrapper.evmKit.receiveAddress.eip55, chainId: chainId), evmKit: adapter.evmKitWrapper.evmKit, storage: Core.shared.safe4CustomTokenStorage, marketKit: Core.shared.marketKit, chainId: chainId)
            service.requestTokens()
            self.service = service
        default: ()
        }
    }

    static func logo(coinUid: String) -> String? {
        Core.shared.userDefaultsStorage.value(for: Safe4Network.logoKey(coinUid: coinUid, chainId: Safe4Network.currentChainId)) ?? Core.shared.userDefaultsStorage.value(for: coinUid.lowercased())
    }

    func updateSRC20Tokens() {
        service?.requestTokens()
    }

    func cancel() {
        service?.cancel()
        service = nil
    }
}
