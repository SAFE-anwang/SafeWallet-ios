import Foundation
import BigInt
import RxSwift
import RxRelay
import RxCocoa
import UniswapKit
import MarketKit
import EvmKit
import ComponentKit

class LiquidityRecordViewModel {
    private var viewItemsRelay = BehaviorRelay<[RecordItem]>(value: [])
    private var loadingRelay = BehaviorRelay<Bool>(value: true)
    private let syncErrorRelay = BehaviorRelay<Bool>(value: false)
    private var errorRelay = BehaviorRelay<String?>(value: nil)
    private var removeStatusRelay = BehaviorRelay<(Bool, String?)>(value: (false, nil))
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
            syncErrorRelay.accept(false)
            
        case .completed(let datas):
            viewItemsRelay.accept(datas)
            loadingRelay.accept(false)
            syncErrorRelay.accept(datas.count == 0)
            
        case .removeSuccess(let datas):
            viewItemsRelay.accept(datas)
            loadingRelay.accept(false)
            syncErrorRelay.accept(datas.count == 0)
            removeStatusRelay.accept((true, "liquidity.remove.succ".localized))
            refresh()
            
        case .failed(error: let error):
            errorRelay.accept(error.localizedDescription)
            loadingRelay.accept(false)
            syncErrorRelay.accept(true)
            
        case .removeFailed(error: let error, data: let data):
            if case JsonRpcResponse.ResponseError.rpcError(_) = error {
                var feeType: String = ""
                switch data.tokenA.blockchainType {
                case .binanceSmartChain:
                    feeType = "BNB"
                case .ethereum:
                    feeType = "ETH"
                default:
                    feeType = ""
                }
                removeStatusRelay.accept((false, "liquidity.remove.error.insufficient".localized(feeType)))
            }else {
                removeStatusRelay.accept((false, error.localizedDescription))
            }
            loadingRelay.accept(false)
            syncErrorRelay.accept(false)
            
        }
    }
}

extension LiquidityRecordViewModel {
    var loadingDriver: Driver<Bool> {
        loadingRelay.asDriver()
    }
    
    var syncErrorDriver: Driver<Bool> {
        syncErrorRelay.asDriver()
    }
    
    var errorDriver: Driver<String?> {
        errorRelay.asDriver()
    }
    
    var viewItemsDriver: Driver<[RecordItem]> {
        viewItemsRelay.asDriver()
    }
    
    var removeStatusDriver: Driver<(Bool, String?)> {
        removeStatusRelay.asDriver()
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
            let liquidity =  liquidity < 0.00000001 ? "<0.00000001" : decimalNumberToInt(value: liquidity, scale: 8)
            return "liquidity.pool.quantity".localized + ":\(liquidity)/\(decimalNumberToInt(value: shareRate * 100, scale: 8))%"
        }
        
        func decimalNumberToInt(value: Decimal, scale: Int) -> String {
            let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: scale), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
            return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).stringValue
        }
    }
}
