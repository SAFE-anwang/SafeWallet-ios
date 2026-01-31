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
        safeProvider.getCrossChainConfigForSafe4Native()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] safeInfo in
                self?.save(safe4NativeConfig: safeInfo)
            })
            .disposed(by: disposeBag)
        
        safeProvider.getCrossChainConfigForSafe4USDT()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] safeInfo in
                self?.save(safe4USDTConfig: safeInfo)
            })
            .disposed(by: disposeBag)
    }
    
}

// SAFE4
extension SafeCrossChainManager {
    private func save(safe4NativeConfig: CrossChainSafe4NativeConfig) {
        if let jsonStr = safe4NativeConfig.toJSONString() {
            userDefaultsStorage.set(value: jsonStr, for: crossChainSafe4_Native_Storage_key)
        }
    }
        
    func getSafe4Native() -> CrossChainSafe4NativeConfig? {
        if let jsonStr: String = userDefaultsStorage.value(for: crossChainSafe4_Native_Storage_key),  let model = try? CrossChainSafe4NativeConfig(JSONString: jsonStr) {
            return model
        }
        return nil
    }
}

// USDT
extension SafeCrossChainManager {
    private func save(safe4USDTConfig: CrossChainSafe4USDTConfig) {
        if let jsonStr = safe4USDTConfig.toJSONString() {
            userDefaultsStorage.set(value: jsonStr, for: crossChainSafe4_USDT_Storage_key)
        }
    }
    
    func getSafe4USDT() -> CrossChainSafe4USDTConfig? {
        if let jsonStr: String = userDefaultsStorage.value(for: crossChainSafe4_USDT_Storage_key),  let model = try? CrossChainSafe4USDTConfig(JSONString: jsonStr) {
            return model
        }
        return nil
    }
}
