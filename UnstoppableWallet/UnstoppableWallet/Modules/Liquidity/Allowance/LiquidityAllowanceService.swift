
import Foundation
import EvmKit
import RxSwift
import RxRelay
import MarketKit

class LiquidityAllowanceService {
    private let spenderAddress: EvmKit.Address
    private let adapterManager: AdapterManager

    private(set) var tokenA: Token?
    private(set) var tokenB: Token?

    private let disposeBag = DisposeBag()
    private var allowanceDisposeBag = DisposeBag()

    private let stateRelay = PublishRelay<State?>()
    private(set) var state: State? {
        didSet {
            if oldValue != state {
                stateRelay.accept(state)
            }
        }
    }

    init(spenderAddress: EvmKit.Address, adapterManager: AdapterManager, evmKit: EvmKit.Kit) {
        self.spenderAddress = spenderAddress
        self.adapterManager = adapterManager

        evmKit.lastBlockHeightObservable
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .observeOn(MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self] blockNumber in
                    self?.sync()
                })
                .disposed(by: disposeBag)
    }

    private func sync() {
        allowanceDisposeBag = DisposeBag()

        guard let tokenA = tokenA, let adapterA = adapterManager.adapter(for: tokenA) as? IErc20Adapter else {
            state = nil
            return
        }
        
        guard let tokenB = tokenB, let adapterB = adapterManager.adapter(for: tokenB) as? IErc20Adapter else {
            state = nil
            return
        }

        if let state = state, case .ready = state {
            // no need to set loading, simply update to new allowance value
        } else {
            state = .loading
        }
        
        Single.zip( adapterA.allowanceSingle(spenderAddress: spenderAddress, defaultBlockParameter: .latest),
                        adapterB.allowanceSingle(spenderAddress: spenderAddress, defaultBlockParameter: .latest))
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onSuccess: { [weak self] allowanceA, allowanceB in
                    self?.state = .ready(allowanceA: CoinValue(kind: .token(token: tokenA), value: allowanceA), allowanceB: CoinValue(kind: .token(token: tokenB), value: allowanceB))
                }, onError: { [weak self] error in
                    self?.state = .notReady(error: error)
                })
                .disposed(by: allowanceDisposeBag)
    }

}

extension LiquidityAllowanceService {

    var stateObservable: Observable<State?> {
        stateRelay.asObservable()
    }

    func set(tokenA: Token?) {
        self.tokenA = tokenA
        sync()
    }
    
    func set(tokenB: Token?) {
        self.tokenB = tokenB
        sync()
    }

    func approveData(dex: LiquidityMainModule.Dex, token: Token?, amount: Decimal) -> ApproveData? {
        
        if case .ready(let allowanceA, let allowanceB) = state {
            
            guard let token else { return nil }
            
            if token == tokenA  {
                return ApproveData(
                        dex: dex,
                        token: token,
                        spenderAddress: spenderAddress,
                        amount: amount,
                        allowance: allowanceA.value
                )
            }
            
            if token == tokenB  {
                return ApproveData(
                        dex: dex,
                        token: token,
                        spenderAddress: spenderAddress,
                        amount: amount,
                        allowance: allowanceB.value
                )
            }
            

        }
        return nil
   
    }

}

extension LiquidityAllowanceService {

    enum State: Equatable {
        case loading
        case ready(allowanceA: CoinValue, allowanceB: CoinValue)
        case notReady(error: Error)

        static func ==(lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.ready(let lhsAllowanceA, let lhsAllowanceB), .ready(let rhsAllowanceA, let rhsAllowanceB)): return lhsAllowanceA == rhsAllowanceA && lhsAllowanceB == rhsAllowanceB
            default: return false
            }
        }
    }

    struct ApproveData {
        let dex: LiquidityMainModule.Dex
        let token: Token
        let spenderAddress: EvmKit.Address
        let amount: Decimal
        let allowance: Decimal
    }

}
