import HsToolKit
import Foundation

class SRC20SyncManager {
    private var service: SyncSafe4TokensService?

    private func diagnosticLog(_ message: @autoclosure () -> String) {
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "background")
        print("[SRC20SyncManager] [\(thread)] \(Date()) \(message())")
    }

    init(wallet: Wallet, adapter: IAdapter) {
        diagnosticLog("init begin account=\(wallet.account.id) chain=\(wallet.token.blockchainType.uid) adapter=\(type(of: adapter))")
        guard wallet.coin.uid.isSafeCoin && wallet.token.blockchain.type == .safe4 &&  wallet.token.type == .native else { return }
        switch adapter {
        case let adapter as ISendEthereumAdapter:
            guard let privateKey = adapter.evmKitWrapper.signer?.privateKey else {
                diagnosticLog("init skipped: adapter has no signer")
                return
            }
            let chainId = adapter.evmKitWrapper.evmKit.chain.id
            let provider = SyncSafe4TokensProvider(networkManager: Core.shared.networkManager, chainId: chainId)
            let service = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey, lockAddress: adapter.evmKitWrapper.evmKit.receiveAddress.eip55, chainId: chainId), evmKit: adapter.evmKitWrapper.evmKit, storage: Core.shared.safe4CustomTokenStorage, marketKit: Core.shared.marketKit, chainId: chainId)
            service.requestTokens()
            self.service = service
            diagnosticLog("init ready chainId=\(chainId)")
        default: ()
            diagnosticLog("init skipped: adapter is not Ethereum-compatible")
        }
    }

    static func logo(coinUid: String) -> String? {
        Core.shared.userDefaultsStorage.value(for: Safe4Network.logoKey(coinUid: coinUid, chainId: Safe4Network.currentChainId)) ?? Core.shared.userDefaultsStorage.value(for: coinUid.lowercased())
    }

    func updateSRC20Tokens(forceRefresh: Bool = false) {
        diagnosticLog("update requested forceRefresh=\(forceRefresh) service=\(service == nil ? "nil" : "present")")
        service?.requestTokens(forceRefresh: forceRefresh)
    }

    func tokensService(chainId: Int) -> SyncSafe4TokensService? {
        guard let service, service.isServingCurrentContext(chainId: chainId) else {
            return nil
        }

        return service
    }

    func cancel() {
        diagnosticLog("cancel begin service=\(service == nil ? "nil" : "present")")
        service?.cancel()
        service = nil
        diagnosticLog("cancel end")
    }
}
