import Foundation
import RxSwift
import RxRelay
import RxCocoa
import EvmKit
import SafeCoinKit
import ObjectMapper
import MarketKit

class SafeCrossChainManager {

    private let evmBlockchainManager: EvmBlockchainManager
    private let userDefaultsStorage: UserDefaultsStorage
    private let safeProvider: SafeProvider
    private let disposeBag = DisposeBag()

    private let crossChainSafe4_Native_Storage_key = "CrossChainSafe4_Native_Storage_key"
    private let crossChainSafe4_USDT_Storage_key = "CrossChainSafe4_USDT_Storage_key"

    init(userDefaultsStorage: UserDefaultsStorage, evmBlockchainManager: EvmBlockchainManager, safeProvider: SafeProvider) {
        self.userDefaultsStorage = userDefaultsStorage
        self.evmBlockchainManager = evmBlockchainManager
        self.safeProvider = safeProvider
        getConfig()
    }

    func getConfig() {
        let chainId = Safe4Network.currentChainId
        safeProvider.getCrossChainConfigForSafe4Native(chainId: chainId)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] safeInfo in
                self?.save(safe4NativeConfig: safeInfo, chainId: chainId)
            })
            .disposed(by: disposeBag)

        safeProvider.getCrossChainConfigForSafe4USDT(chainId: chainId)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] safeInfo in
                self?.save(safe4USDTConfig: safeInfo, chainId: chainId)
            })
            .disposed(by: disposeBag)
    }

}

// SAFE4
extension SafeCrossChainManager {
    private func save(safe4NativeConfig: CrossChainSafe4NativeConfig, chainId: Int) {
        if let jsonStr = safe4NativeConfig.toJSONString() {
            userDefaultsStorage.set(value: jsonStr, for: Safe4CacheScope(chainId: chainId).key(crossChainSafe4_Native_Storage_key))
        }
    }

    func getSafe4Native(chainId: Int = Safe4Network.currentChainId) -> CrossChainSafe4NativeConfig? {
        if let jsonStr: String = userDefaultsStorage.value(for: Safe4CacheScope(chainId: chainId).key(crossChainSafe4_Native_Storage_key)),  let model = try? CrossChainSafe4NativeConfig(JSONString: jsonStr) {
            return model
        }
        return nil
    }
}

// USDT
extension SafeCrossChainManager {
    private func save(safe4USDTConfig: CrossChainSafe4USDTConfig, chainId: Int) {
        if let jsonStr = safe4USDTConfig.toJSONString() {
            userDefaultsStorage.set(value: jsonStr, for: Safe4CacheScope(chainId: chainId).key(crossChainSafe4_USDT_Storage_key))
        }
    }

    func getSafe4USDT(chainId: Int = Safe4Network.currentChainId) -> CrossChainSafe4USDTConfig? {
        if let jsonStr: String = userDefaultsStorage.value(for: Safe4CacheScope(chainId: chainId).key(crossChainSafe4_USDT_Storage_key)),  let model = try? CrossChainSafe4USDTConfig(JSONString: jsonStr) {
            return model
        }
        return nil
    }
}
