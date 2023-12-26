import Foundation
import EvmKit
import RxSwift
import RxRelay
import MarketKit

class LiquidityPendingAllowanceService {
    private let spenderAddress: EvmKit.Address
    private let adapterManager: AdapterManager
    private let allowanceService: LiquidityAllowanceService
    
    private(set) var tokenA: Token?
    private(set) var tokenB: Token?
    private var pendingAllowanceA: Decimal?
    private var pendingAllowanceB: Decimal?


    private let disposeBag = DisposeBag()

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notAllowed {
        didSet {
            if oldValue != state {
                stateRelay.accept(state)
            }
        }
    }

    init(spenderAddress: EvmKit.Address, adapterManager: AdapterManager, allowanceService: LiquidityAllowanceService) {
        self.spenderAddress = spenderAddress
        self.adapterManager = adapterManager
        self.allowanceService = allowanceService
        
        allowanceService.stateObservable
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .observeOn(MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self] _ in
                    self?.sync()
                })
                .disposed(by: disposeBag)
    }

    private func sync() {
//        print("Pending allowance: \(pendingAllowance ?? -1)")
        guard let pendingAllowanceA = pendingAllowanceA, let pendingAllowanceB = pendingAllowanceB else {
            state = .notAllowed
            return
        }

//        print("allowance state: \(allowanceService.state)")
        guard case .ready(let allowanceA, let allowanceB) = allowanceService.state else {
            state = .notAllowed
            return
        }

        if pendingAllowanceA != allowanceA.value {
            state = pendingAllowanceA == 0 ? .revoking : .pending
        }else if pendingAllowanceB != allowanceB.value {
            state = pendingAllowanceB == 0 ? .revoking : .pending
        }else {
            state = .approved
        }
    }

}

extension LiquidityPendingAllowanceService {

    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    func set(tokenA: Token?) {
        self.tokenA = tokenA
        pendingAllowanceA = nil
        syncAllowance()
    }
    
    func set(tokenB: Token?) {
        self.tokenB = tokenB
        pendingAllowanceB = nil
        syncAllowance()
    }

    func syncAllowance() {
        guard let tokenA = tokenA, let adapterA = adapterManager.adapter(for: tokenA) as? IErc20Adapter else {
            return
        }
        
        guard let tokenB = tokenB, let adapterB = adapterManager.adapter(for: tokenB) as? IErc20Adapter else {
            return
        }

        for transaction in adapterA.pendingTransactions {
            if let approve = transaction as? ApproveTransactionRecord, let value = approve.value.decimalValue {
                pendingAllowanceA = value
            }
        }
        
        for transaction in adapterB.pendingTransactions {
            if let approve = transaction as? ApproveTransactionRecord, let value = approve.value.decimalValue {
                pendingAllowanceB = value
            }
        }

        sync()
    }

}

extension LiquidityPendingAllowanceService {

    enum State: Int {
        case notAllowed, revoking, pending, approved
    }

}

