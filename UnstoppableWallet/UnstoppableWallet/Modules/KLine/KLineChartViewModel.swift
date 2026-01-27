import Combine
import Foundation
import MarketKit
import RxSwift

class KLineChartViewModel: ObservableObject {
    
    private var disposeBag = DisposeBag()
    private let provider: Safe4Provider
    private let token0: MarketKit.Token
    private let token1: MarketKit.Token
    @Published var price: KLineWSafeTokenPriceModel?
    
    init(provider: Safe4Provider, token0: MarketKit.Token, token1: MarketKit.Token) {
        self.provider = provider
        self.token0 = token0
        self.token1 = token1
        getPrices()
    }
    
    private func getPrices() {
        provider.wsafePricesSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { datas in
                DispatchQueue.main.async {
                    self.showPrice(models: datas)
                }
            }, onError: { error in
                
            })
            .disposed(by: disposeBag)
    }
    
    private func showPrice(models: [KLineWSafeTokenPriceModel]) {
        if token0.coin.code == "USDT", case let .eip20(token1Address) = token1.type {
            price = models.filter{$0.address.lowercased() == token1Address.lowercased() }.first
        } else if token1.coin.code == "USDT", case let .eip20(token0Address) = token0.type {
            price = models.filter{$0.address.lowercased() == token0Address.lowercased() }.first
        }
    }

}
