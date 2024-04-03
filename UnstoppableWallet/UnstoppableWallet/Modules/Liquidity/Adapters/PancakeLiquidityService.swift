import RxSwift
import RxRelay
import HsToolKit
import UniswapKit
import BigInt
import EvmKit
import Foundation
import MarketKit

class PancakeLiquidityService {
    let dex: LiquidityMainModule.Dex
    private let tradeService: PancakeLiquidityTradeService
    
    private let allowanceService: LiquidityAllowanceService
    private let pendingAllowanceService: LiquidityPendingAllowanceService
    private let adapterManager: AdapterManager

    private let disposeBag = DisposeBag()

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notReady {
        didSet {
            if oldValue != state {
                stateRelay.accept(state)
            }
        }
    }

    private let errorsRelay = PublishRelay<[Error]>()
    private(set) var errors: [Error] = [] {
        didSet {
            if oldValue.isEmpty && errors.isEmpty {
                return
            }
            errorsRelay.accept(errors)
        }
    }

    private let balanceInRelay = PublishRelay<Decimal?>()
    private(set) var balanceIn: Decimal? {
        didSet {
            balanceInRelay.accept(balanceIn)
        }
    }

    private let balanceOutRelay = PublishRelay<Decimal?>()
    private(set) var balanceOut: Decimal? {
        didSet {
            balanceOutRelay.accept(balanceOut)
        }
    }

    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "anwang.safewallet.liquidity_service")

    init(dex: LiquidityMainModule.Dex, tradeService: PancakeLiquidityTradeService, allowanceService: LiquidityAllowanceService, pendingAllowanceService: LiquidityPendingAllowanceService, adapterManager: AdapterManager) {
        self.dex = dex
        self.tradeService = tradeService
        
        self.allowanceService = allowanceService
        self.pendingAllowanceService = pendingAllowanceService
        
        self.adapterManager = adapterManager

        subscribe(scheduler, disposeBag, tradeService.stateObservable) { [weak self] state in
            self?.onUpdateTrade(state: state)
        }

        subscribe(scheduler, disposeBag, tradeService.tokenInObservable) { [weak self] token in
            self?.onUpdate(token: token)
        }
        onUpdate(token: tradeService.tokenIn)

        subscribe(scheduler, disposeBag, tradeService.tokenOutObservable) { [weak self] token in
            self?.onUpdate(tokenOut: token)
        }
        onUpdate(tokenOut: tradeService.tokenOut)

        subscribe(scheduler, disposeBag, tradeService.amountInObservable) { [weak self] amount in
            self?.onUpdate(amountIn: amount)
        }
        subscribe(scheduler, disposeBag, allowanceService.stateObservable) { [weak self] _ in
            self?.syncState()
        }
  
        subscribe(scheduler, disposeBag, pendingAllowanceService.stateObservable) { [weak self] _ in
            self?.onUpdatePendingAllowanceState()
        }
    }

    private func onUpdateTrade(state: PancakeLiquidityTradeService.State) {
        syncState()
    }

    private func onUpdate(token: MarketKit.Token?) {
        balanceIn = token.flatMap { balance(token: $0) }
        allowanceService.set(tokenA: token)
        pendingAllowanceService.set(tokenA: token)
    }

    private func onUpdate(amountIn: Decimal?) {
        syncState()
    }

    private func onUpdate(tokenOut: MarketKit.Token?) {
        balanceOut = tokenOut.flatMap { balance(token: $0) }
        allowanceService.set(tokenB: tokenOut)
        pendingAllowanceService.set(tokenB: tokenOut)
    }

    private func onUpdatePendingAllowanceState() {
        syncState()
    }

    private func checkAllowanceError(allowance: CoinValue) -> Error? {
        guard let balanceIn = balanceIn,
              balanceIn >= tradeService.amountIn,
              tradeService.amountIn > allowance.value else {
            return nil
        }

        if SwapModule.mustBeRevoked(token: tradeService.tokenIn), allowance.value != 0 {
            return SwapModule.SwapError.needRevokeAllowance(allowance: allowance)
        }

        return SwapModule.SwapError.insufficientAllowance
    }
    
    private func checkAllowanceBError(allowance: CoinValue) -> Error? {
        guard let balanceOut = balanceOut,
              balanceOut >= tradeService.amountOut,
                tradeService.amountOut > allowance.value else {
            return nil
        }

        if SwapModule.mustBeRevoked(token: tradeService.tokenOut), allowance.value != 0 {
            return SwapModule.SwapError.needRevokeAllowance(allowance: allowance)
        }

        return SwapModule.SwapError.insufficientAllowanceB
    }

    private func syncState() {
        var allErrors = [Error]()
        var loading = false

        var transactionData: TransactionData?

        switch tradeService.state {
        case .loading:
            loading = true
        case .ready(let trade):
            transactionData = try? tradeService.transactionData(tradeData: trade.tradeData)
        case .notReady(let errors):
            allErrors.append(contentsOf: errors)
        }
        let (allError, loadingA) = syncState(allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
        
        allErrors.append(contentsOf: allError)
        
        loading = loadingA

        if !loading {
            errors = allErrors
        }

        if loading {
            state = .loading
        } else if let transactionData = transactionData, allErrors.isEmpty {
            state = .ready(transactionData: transactionData)
        } else {
            state = .notReady
        }
    }
    
    private func syncState(allowanceService: LiquidityAllowanceService, pendingAllowanceService: LiquidityPendingAllowanceService) -> ([Error], Bool) {
        
        var allErrors = [Error]()
        var loading = false
        
        if let allowanceState = allowanceService.state {
            switch allowanceState {
            case .loading:
                loading = true
            case .ready(let allowanceA, let allowanceB):
                if let error = checkAllowanceError(allowance: allowanceA) {
                    allErrors.append(error)
                }
                
                if let error = checkAllowanceBError(allowance: allowanceB) {
                    allErrors.append(error)
                }
            case .notReady(let error):
                allErrors.append(error)
            }
        }

        if allowanceService.tokenA?.coin == tradeService.tokenIn?.coin, let balanceIn = balanceIn, allowanceService.tokenB?.coin == tradeService.tokenOut?.coin, let balanceOut = balanceOut {
            if tradeService.amountIn > balanceIn {
                allErrors.append(SwapModule.SwapError.insufficientBalanceIn)
            }
            
            if tradeService.amountOut > balanceOut {
                allErrors.append(SwapModule.SwapError.insufficientBalanceIn2)
            }
        } else {
            allErrors.append(SwapModule.SwapError.noBalanceIn)
        }

        if pendingAllowanceService.state == .pending {
            loading = true
        }
        return (allErrors, loading)
    }

    private func balance(token: MarketKit.Token) -> Decimal? {
        (adapterManager.adapter(for: token) as? IBalanceAdapter)?.balanceData.available
    }

}

extension PancakeLiquidityService: ISwapErrorProvider {

    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var errorsObservable: Observable<[Error]> {
        errorsRelay.asObservable()
    }

    var balanceInObservable: Observable<Decimal?> {
        balanceInRelay.asObservable()
    }

    var balanceOutObservable: Observable<Decimal?> {
        balanceOutRelay.asObservable()
    }

    func approveData(amount: Decimal? = nil)  -> LiquidityAllowanceService.ApproveData? {
        
        let (allErrors, _) = syncState(allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
       
        if !allErrors.isEmpty {
            
            if allErrors.contains(where: { .insufficientAllowance == $0 as? SwapModule.SwapError }) {
                let amount = amount ?? balanceIn
                guard let amount = amount else {
                    return nil
                }
                let token = allowanceService.tokenA
                return allowanceService.approveData(dex: dex, token: token, amount: amount)
                
            } else if allErrors.contains(where: { .insufficientAllowanceB == $0 as? SwapModule.SwapError }) {
                let amount = amount ?? balanceOut
                guard let amount = amount else {
                    return nil
                }
                let token = allowanceService.tokenB
                return allowanceService.approveData(dex: dex, token: token, amount: amount)
            }
        }
        return nil
    }
}

extension PancakeLiquidityService {

    enum State: Equatable {
        case loading
        case ready(transactionData: TransactionData)
        case notReady

        static func ==(lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.ready(let lhsTransactionData), .ready(let rhsTransactionData)): return lhsTransactionData == rhsTransactionData
            case (.notReady, .notReady): return true
            default: return false
            }
        }
    }

}
