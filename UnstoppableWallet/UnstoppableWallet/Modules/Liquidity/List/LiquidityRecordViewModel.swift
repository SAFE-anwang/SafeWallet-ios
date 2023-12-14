import Foundation
import BigInt
import RxSwift
import RxRelay
import RxCocoa
import UniswapKit
import CurrencyKit
import MarketKit
import EvmKit

class LiquidityRecordViewModel {
    private var viewItemsRelay = BehaviorRelay<[RecordItem]>(value: [])
    private var loadingRelay = BehaviorRelay<Bool>(value: false)
    private let service: LiquidityRecordService
    private var disposeBag = DisposeBag()

    init(service: LiquidityRecordService) {
        self.service = service
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
    }
    
    private func sync(state: LiquidityRecordService.State) {
        switch state {
        case .loading:
            loadingRelay.accept(true)

        case .completed(let datas):
            viewItemsRelay.accept(datas)
            loadingRelay.accept(false)
        case .failed:
            loadingRelay.accept(false)
        }
    }
}

extension LiquidityRecordViewModel {
    var loadingDriver: Driver<Bool> {
        loadingRelay.asDriver()
    }
    
    var viewItemsDriver: Driver<[RecordItem]> {
        viewItemsRelay.asDriver()
    }
    
    func removeLiquidity(recordItem: RecordItem) {
        service.removeLiquidity(viewItem: recordItem)
    }
    
    func refresh() {
        service.refresh()
    }
}

extension LiquidityRecordViewModel {
    
    struct RecordItem {
        let tokenA: MarketKit.Token
        let tokenB: MarketKit.Token
        let amountA: Decimal
        let amountB: Decimal
        let liquidity: Decimal
        let shareRate: Decimal
        let totalSupply: Decimal
        let pair: LiquidityPair
        
        var amountAStr: String {
            decimalNumberToInt(value: amountA, scale: 8)
        }
        
        var amountBStr: String {
            decimalNumberToInt(value: amountB, scale: 8)
        }
        
        var liquidityDec: String {
            "liquidity.pool.quantity".localized + ":\(decimalNumberToInt(value: liquidity, scale: 5))/\(decimalNumberToInt(value: shareRate * 100, scale: 8))%"
        }
        
        func decimalNumberToInt(value: Decimal, scale: Int) -> String {
            let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: scale), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
            return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).stringValue
        }
    }
}
