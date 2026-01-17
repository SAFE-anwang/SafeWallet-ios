import Combine
import SwiftUI
import Foundation
import MarketKit
import EvmKit
import RxSwift

class PreSendAllowanceHandler: ObservableObject {
    private let token: Token
    private let allowanceHelper = MultiSwapAllowanceHelper()
    private let evmBlockchainManager = Core.shared.evmBlockchainManager
    private(set) var allowanceState: MultiSwapAllowanceHelper.AllowanceState?
    private(set) var allowedAmount: Decimal = 0
    private(set) var pendingAllowanceAmount: Decimal = 0
    private(set) var preSendAmount: Decimal = 0
    private(set) var allowanceSyncing = false
    private(set) var sendApprovelastBlockHeight: Int = 0
    private var onSuccess: ((MultiSwapAllowanceHelper.AllowanceState?) -> Void)? = nil
    private let disposeBag = DisposeBag()
    init(token: Token) {
        self.token = token
        
        if let eip20Adapter = Core.shared.adapterManager.adapter(for: token) as? Eip20Adapter {
            subscribe(disposeBag, eip20Adapter.lastBlockUpdatedObservable) { [weak self] in
                guard let self = self else { return }
                guard case .pendingAllowance = allowanceState else { return }
                guard onSuccess != nil else {return }
                if self.sendApprovelastBlockHeight > 0, let lastBlockHeight = eip20Adapter.lastBlockInfo?.height, lastBlockHeight >= (self.sendApprovelastBlockHeight + 1) {
                    let allowanceState: MultiSwapAllowanceHelper.AllowanceState = .allowed
                    self.allowanceState = allowanceState
                    onSuccess?(allowanceState)
                }
            }
        }
    }
}
extension PreSendAllowanceHandler {
    
    var scr20TimeLockAddress: String {
        if isSafe4TestNet {
            "0x4f203092FB68732D8484c099a72dDc5a195f26f9"
        } else {
            "0x6A6dFAF83cc1741FE08A9EFDea596dEad68f7420"
        }
    }
    
    func getAllowanceState(amount: Decimal, availableBalance: Decimal, onSuccess: @escaping (MultiSwapAllowanceHelper.AllowanceState?) -> Void) {
        self.onSuccess = onSuccess
        preSendAmount = amount
        if allowedAmount == 0, !allowanceSyncing {
            syncAllowanceState(amount: availableBalance, onSuccess: onSuccess)
        }else if allowedAmount > 0, amount <= allowedAmount {
            self.allowanceState = nil
            onSuccess(nil)
            
        } else if allowedAmount > 0, amount > allowedAmount {
            if pendingAllowanceAmount > 0, amount <= pendingAllowanceAmount {
                let allowanceState: MultiSwapAllowanceHelper.AllowanceState = .pendingAllowance(appValue:AppValue(value: pendingAllowanceAmount))
                self.allowanceState = allowanceState
                onSuccess(allowanceState)
            }else {
                syncAllowanceState(amount: amount, onSuccess: onSuccess)
            }
        } else {
            syncAllowanceState(amount: amount, onSuccess: onSuccess)
        }
    }
    
    func syncAllowanceState(amount: Decimal, onSuccess: @escaping (MultiSwapAllowanceHelper.AllowanceState?) -> Void) {
        allowanceSyncing = true
        Task {
            let allowanceState = await allowanceState(amount: amount)
            
            if case let .notEnough(appValue, _, _) = allowanceState {
                allowedAmount = appValue.value
            }
            if case let .pendingAllowance(appValue) = allowanceState {
                pendingAllowanceAmount = appValue.value
            }
            self.allowanceState = allowanceState
            allowanceSyncing = false
            onSuccess(allowanceState)
        }
    }
    
    func preSwapView(step: MultiSwapPreSwapStep, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView {
        allowanceHelper.preSwapView(step: step, tokenIn: token, amount: amount, isPresented: isPresented) {
            if let eip20Adapter = Core.shared.adapterManager.adapter(for:  self.token) as? Eip20Adapter {
                self.sendApprovelastBlockHeight = eip20Adapter.lastBlockInfo?.height ?? 0
            }
            onSuccess()
        }
    }
    
    private func allowanceState(amount: Decimal) async -> MultiSwapAllowanceHelper.AllowanceState {
       return await allowanceHelper.allowanceState(spenderAddress: .init(raw: scr20TimeLockAddress), token: token, amount: amount)
    }
}
