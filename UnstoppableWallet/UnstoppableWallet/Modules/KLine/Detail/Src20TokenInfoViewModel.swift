import UIKit
import Combine
import Foundation
import MarketKit
import RxSwift

class Src20TokenInfoViewModel: ObservableObject {
    let token: MarketKit.Token
    private var disposeBag = DisposeBag()
    private let provider: Safe4Provider
    private let storage = Core.shared.safe4CustomTokenStorage
    private var srC20Service: SRC20Service?
    
    @Published var viewItems = [KLineWSafeTokenPriceModel]()
    @Published var currentToken: KLineWSafeTokenPriceModel?
    @Published var totalSupply: String = ""
    @Published var description: String = ""
    @Published var canAdditionalIssuance: Bool = false
    init(provider: Safe4Provider, token: MarketKit.Token) {
        self.provider = provider
        self.token = token
        getPrices()
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return
        }
        
        if case let .eip20(address) = token.type {
            if let tokenRecord = try? storage.asset(address: address) {
                let service = SRC20Service(token: tokenRecord, privateKey: privateKey, lockAddress: evmKitWrapper.evmKit.receiveAddress.eip55)
                self.canAdditionalIssuance = tokenRecord.canAdditionalIssuance
                Task {
                    do {
                        let totalSupply = try await service.totalSupply(type: tokenRecord.deployType)
                        let description = try await service.description(type: tokenRecord.deployType)
                        DispatchQueue.main.async {
                            self.totalSupply = totalSupply.safe4FomattedAmount.description
                            self.description = description
                        }
                    }catch {
                        print("")
                    }
                }
            }
        }
    }
}

extension Src20TokenInfoViewModel {
    private func getPrices() {
        provider.wsafePricesSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { datas in
                DispatchQueue.main.async {
                    self.viewItems = datas
                    self.showPrice(models: datas)
                }
            }, onError: { error in
                
            })
            .disposed(by: disposeBag)
    }
    
    private func showPrice(models: [KLineWSafeTokenPriceModel]) {
        if case let .eip20(tokenAddress) = token.type {
            currentToken = models.filter{$0.address.lowercased() == tokenAddress.lowercased() }.first
        }
    }
}
