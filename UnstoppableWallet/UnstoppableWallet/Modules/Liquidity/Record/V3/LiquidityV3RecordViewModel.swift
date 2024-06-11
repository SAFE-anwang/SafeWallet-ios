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

class LiquidityV3RecordViewModel {
    private var statusRelay = PublishRelay<LiquidityV3RecordService.State>()
    private var service: LiquidityV3RecordService?
    private var disposeBag = DisposeBag()
    
    init(service: LiquidityV3RecordService?) {
        self.service = service
        subscribe(disposeBag, service?.stateObservable) { [weak self] in self?.sync(state: $0) }
    }
    
    private func sync(state: LiquidityV3RecordService.State) {
        statusRelay.accept(state)
    }
}
extension LiquidityV3RecordViewModel {
    var statusDriver: Observable<LiquidityV3RecordService.State> {
        statusRelay.asObservable()
    }

    func removeLiquidity(recordItem: V3RecordItem, ratio: BigUInt) {
        service?.removeLiquidity(item: recordItem, ratio: ratio)
    }
    
    func refresh() {
        service?.refresh()
    }
}

extension LiquidityV3RecordViewModel {
    
    struct V3RecordItem {
        let positions: Positions
        let token0: MarketKit.Token
        let token1: MarketKit.Token
        let isInRange: Bool
        let token0Amount: BigUInt
        let token1Amount: BigUInt
        let lowerPrice: Decimal?
        let upperPrice: Decimal?
        
        var tokenId: String {
            "#(\(positions.tokenId))"
        }
        
        var lpName: String {
            "\(token1.coin.code)-\(token0.coin.code) LP"
        }
        
        var fee: String {
            "\(Float(positions.fee) / 1000)%"
        }
        
        private let space = " "
        var tickRangeDesc: String {
            "liquidity.tick.min".localized  + space + lowerPriceStr + " / " + "liquidity.tick.max".localized + space + upperPriceStr + space + token1.coin.code + "/" + token0.coin.code
        }
        
        var lowerPriceStr: String {
            if positions.tickUpper == TickMath.MIN_TICK { return "0" }
            guard let price = lowerPrice else{ return "" }
            return decimalNumberToInt(value: price, scale: 5)
        }
        
        var upperPriceStr: String {
            if positions.tickUpper == TickMath.MAX_TICK { return "∞" }
            guard let price = upperPrice else{ return "" }
            return decimalNumberToInt(value: price, scale: 5)
        }
        
        var state: String {
            isInRange ? "liquidity.tick.state.active".localized : "liquidity.tick.state.inactive".localized
        }
        
        var color: UIColor {
            isInRange ?  .themeRemus : .themeLucian
        }
        
        func token0Amount(ratio: Float) -> String {
            let amount = token0Amount * BigUInt(Int(ratio * 100)) / 100
            let decimal = Decimal(bigUInt: amount, decimals: token0.decimals) ?? 0
            return ratioFormatter.string(from: decimal as NSNumber) ?? ""
        }
        
        func token1Amount(ratio: Float) -> String {
            let amount = token1Amount * BigUInt(Int(ratio * 100)) / 100
            let decimal = Decimal(bigUInt: amount, decimals: token1.decimals) ?? 0
            return ratioFormatter.string(from: decimal as NSNumber) ?? ""
        }

        private let ratioFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.roundingMode = .halfUp
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
            return formatter
        }()
        
        func decimalNumberToInt(value: Decimal, scale: Int) -> String {
            let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: scale), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
            return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).stringValue
        }
    }
}
