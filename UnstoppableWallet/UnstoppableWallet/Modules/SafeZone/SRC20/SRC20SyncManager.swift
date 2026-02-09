import HsToolKit
import Foundation

class SRC20SyncManager {
    private var service: SyncSafe4TokensService?
    
    init(wallet: Wallet, adapter: IAdapter) {
        guard wallet.coin.uid.isSafeCoin && wallet.token.blockchain.type == .safe4 &&  wallet.token.type == .native else { return }
        let provider = SyncSafe4TokensProvider(networkManager: Core.shared.networkManager)
        switch adapter {
        case let adapter as ISendEthereumAdapter:
            guard let privateKey = adapter.evmKitWrapper.signer?.privateKey else {
                return
            }
            let service = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey, lockAddress: adapter.evmKitWrapper.evmKit.receiveAddress.eip55), evmKit: adapter.evmKitWrapper.evmKit, storage: Core.shared.safe4CustomTokenStorage, marketKit: Core.shared.marketKit)
            service.requestTokens()
            self.service = service
        default: ()
        }
    }
    
    static func logo(coinUid: String) -> String? {
        Core.shared.userDefaultsStorage.value(for: coinUid.lowercased())
    }

    func updateSRC20Tokens() {
        service?.requestTokens()
    }

}
