import HsToolKit
import Foundation

class SRC20SyncManager {
    private var service: SyncSafe4TokensService?
    private var timer: DispatchSourceTimer?
    
    init(wallet: Wallet, adapter: IAdapter) {
        guard wallet.coin.uid.isSafeCoin && wallet.token.blockchain.type == .safe4 &&  wallet.token.type == .native else { return }
        let provider = SyncSafe4TokensProvider(networkManager: App.shared.networkManager)
        switch adapter {
        case let adapter as ISendEthereumAdapter:
            guard let privateKey = adapter.evmKitWrapper.signer?.privateKey else {
                return
            }
            let service = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey), evmKit: adapter.evmKitWrapper.evmKit, storage: App.shared.safe4CustomTokenStorage, marketKit: App.shared.marketKit)
            service.requestTokens()
            self.service = service
            
            startTimer()
        default: ()
        }
    }
    
    static func logo(coinUid: String) -> String? {
        App.shared.userDefaultsStorage.value(for: coinUid.lowercased())
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(deadline: .now(), repeating: 10)
        timer.setEventHandler {
            self.updateTime()
        }
        self.timer = timer
        timer.resume()
    }

    private func updateTime() {
        service?.requestTokens()
    }

    deinit {
        timer?.cancel()
    }
}
