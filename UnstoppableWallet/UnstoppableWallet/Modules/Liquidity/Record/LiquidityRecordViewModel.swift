import Foundation
import UIKit
import BigInt
import RxSwift
import RxRelay
import RxCocoa
import UniswapKit
import MarketKit
import EvmKit
import ComponentKit

class LiquidityRecordViewModel {
//    private var viewItemsRelay = BehaviorRelay<[RecordItem]>(value: [])
    private var statusRelay = PublishRelay<LiquidityRecordService.State>()
    private let service: LiquidityRecordService
    private var disposeBag = DisposeBag()

    init(service: LiquidityRecordService) {
        self.service = service
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
    }
    private func sync(state: LiquidityRecordService.State) {
        statusRelay.accept(state)
    }
}

extension LiquidityRecordViewModel {
    
    var statusDriver: Observable<LiquidityRecordService.State> {
        statusRelay.asObservable()
    }

    func removeLiquidity(recordItem: RecordItem, ratio: BigUInt) {
        service.removeLiquidity(viewItem: recordItem, ratio: ratio)
    }
    
    func refresh() {
        service.refresh()
    }
}

extension LiquidityRecordViewModel {
    
    struct RecordItem {
        let poolInfo: LiquidityRecordService.PoolInfo
        let pair: LiquidityPair
        
        var tokenA: MarketKit.Token {
            pair.item0.token
        }
        var tokenB: MarketKit.Token {
            pair.item1.token
        }

        var amountA: Decimal {
            Decimal(bigUInt: poolInfo.userToken0Amount, decimals: tokenA.decimals) ?? 0
        }
        var amountB: Decimal {
            Decimal(bigUInt: poolInfo.userToken1Amount, decimals: tokenB.decimals) ?? 0
        }
        
        var liquidity: Decimal {
            Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 18) ?? 0
        }
        
        var  shareRate: Decimal {
            poolInfo.shareRate
        }
        
        var totalSupply: Decimal {
            Decimal(bigUInt: poolInfo.poolTokenTotalSupply, decimals: 16) ?? 0
        }
        
        var amountAStr: String {
            decimalNumberToInt(value: amountA, scale: 8)
        }
        
        var amountBStr: String {
            decimalNumberToInt(value: amountB, scale: 8)
        }
        
        var liquidityDec: String {
            let liquidity =  liquidity < 0.00000001 ? "<0.00000001" : decimalNumberToInt(value: liquidity, scale: 8)
            return "liquidity.pool.quantity".localized + ":\(liquidity)/\(decimalNumberToInt(value: shareRate * 100, scale: 8))%"
        }
        
        func decimalNumberToInt(value: Decimal, scale: Int) -> String {
            let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: scale), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
            return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).stringValue
        }
    }
}


