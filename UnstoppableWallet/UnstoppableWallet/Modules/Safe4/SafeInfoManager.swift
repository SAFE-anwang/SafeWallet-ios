import Foundation
import RxSwift
import RxRelay
import RxCocoa
import ComponentKit
import EvmKit
import SafeCoinKit
import ObjectMapper

class SafeInfoManager {

    private let evmBlockchainManager: EvmBlockchainManager
    private let safeProvider: SafeProvider
    
    private let disposeBag = DisposeBag()
    
    private let safeInfoStorageKey = "SafeInfoStorage_key"

    init(evmBlockchainManager: EvmBlockchainManager, safeProvider: SafeProvider) {
        self.evmBlockchainManager = evmBlockchainManager
        self.safeProvider = safeProvider
    }
    
    func startNet() {
        let chain = evmBlockchainManager.evmKitManager(blockchainType: .ethereum).evmKitWrapper?.evmKit.chain ?? Chain.ethereum
        let wsafeKit = WSafeKit(chain: chain)
        do {
            let safeNetType = try wsafeKit.getSafeNetType()
            safeProvider.getSafeInfo(netType: safeNetType)
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onSuccess: { [weak self] safeInfo in
                    self?.save(safeInfo: safeInfo)
                })
                .disposed(by: disposeBag)
        }catch { }
    }
    
    func save(safeInfo: SafeChainInfo) {
        UserDefaults.standard.set(safeInfo.toJSONString(), forKey: safeInfoStorageKey)
        UserDefaults.standard.synchronize()
    }
    
    func getSafeInfo() throws -> SafeChainInfo {
        if let safeInfoJSON = UserDefaults.standard.object(forKey: safeInfoStorageKey) as? String,
           let safeInfo = try? SafeChainInfo(JSONString: safeInfoJSON) {
            return safeInfo
        }else {
            let chain = evmBlockchainManager.evmKitManager(blockchainType: .ethereum).evmKitWrapper?.evmKit.chain ?? Chain.ethereum
            return try defaultSafeInfo(chain: chain)
        }
    
    }
    
    private func defaultSafeInfo(chain: Chain) throws -> SafeChainInfo {

        if chain == .ethereum {

            let minNet = SafeChainInfo(safe_usdt: 0, minamount: 2,
                                  eth: EthChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0.25, safe2eth: true, eth2safe: true),
                                  bsc: BscChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0.25, safe2bsc: true, bsc2safe: true),
                                  matic: MaticChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0.25, safe2matic: true, matic2safe: true))
            return minNet

        }else if chain == .ethereumRopsten {
            let testNet = SafeChainInfo(safe_usdt: 0, minamount: 0.01,
                                   eth: EthChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0, safe2eth: true, eth2safe: true),
                                   bsc: BscChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0, safe2bsc: true, bsc2safe: true),
                                   matic: MaticChainInfo(price: 0, gas_price_gwei: 0, safe_fee: 0.25, safe2matic: true, matic2safe: true))
            return testNet
        }else {
            throw WSafeKit.UnsupportedChainError.noSafeNetType
        }


    }
}
