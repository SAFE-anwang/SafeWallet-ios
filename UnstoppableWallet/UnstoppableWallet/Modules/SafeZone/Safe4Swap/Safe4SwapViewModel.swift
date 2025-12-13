import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import BigInt
import Web3Core
import web3swift
import EvmKit

class Safe4SwapViewModel: ObservableObject {
    let autoRefreshDuration: Double = 20
    
    private var cancellables = Set<AnyCancellable>()
    private var balanceDisposeBag = DisposeBag()
    
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let walletManager = Core.shared.walletManager
    private let adapterManager = Core.shared.adapterManager
    private let decimalParser = AmountDecimalParser()
    
    @Published var currency: Currency

    private var internalTokenIn: Token? {
        didSet {
            guard internalTokenIn != oldValue else {
                return
            }
            
            if internalTokenIn != tokenIn {
                tokenIn = internalTokenIn
            }
            
            balanceDisposeBag = .init()
            
            if let internalTokenIn,
               let wallet = walletManager.activeWallets.first(where: { $0.token == internalTokenIn }),
               let adapter = adapterManager.balanceAdapter(for: wallet)
            {
                if case .eip20 = internalTokenIn.type {
                    updateScr20Balance(wallet: wallet)
                }
                adapterState = adapter.balanceState
                availableBalanceIn = adapter.balanceData.available
                
                adapter.balanceStateUpdatedObservable
                    .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe { [weak self] state in
                        self?.adapterState = state
                    }
                    .disposed(by: balanceDisposeBag)
                
                adapter.balanceDataUpdatedObservable
                    .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] balanceData in
                        self?.availableBalanceIn = balanceData.available
                    }
                    .disposed(by: balanceDisposeBag)
            } else {
                adapterState = nil
                availableBalanceIn = nil
            }
        }
    }
    
    @Published var tokenIn: Token? {
        didSet {
            guard internalTokenIn != tokenIn else {
                return
            }
            amountIn = nil
            
            internalTokenIn = tokenIn
            
            if internalTokenOut == tokenIn {
                internalTokenOut = nil
            }
        }
    }
    
    private var internalTokenOut: Token? {
        didSet {
            guard internalTokenOut != oldValue else {
                return
            }
            
            if internalTokenOut != tokenOut {
                tokenOut = internalTokenOut
            }
            
            if let internalTokenOut,
               let wallet = walletManager.activeWallets.first(where: { $0.token == internalTokenOut }),
               let adapter = adapterManager.balanceAdapter(for: wallet)
            {
                if case .eip20 = internalTokenOut.type {
                    updateScr20Balance(wallet: wallet)
                }
                adapterOutState = adapter.balanceState
                availableBalanceOut = adapter.balanceData.available
                
                adapter.balanceStateUpdatedObservable
                    .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe { [weak self] state in
                        self?.adapterOutState = state
                    }
                    .disposed(by: balanceDisposeBag)
                
                adapter.balanceDataUpdatedObservable
                    .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] balanceData in
                        self?.availableBalanceOut = balanceData.available
                    }
                    .disposed(by: balanceDisposeBag)
            } else {
                adapterOutState = nil
                availableBalanceOut = nil
            }
        }
    }
    
    @Published var tokenOut: Token? {
        didSet {
            guard internalTokenOut != tokenOut else {
                return
            }
            
            internalTokenOut = tokenOut
            
            if internalTokenIn == tokenOut {
                amountIn = nil
                internalTokenIn = nil
            }
        }
    }
    
    @Published var adapterState: AdapterState?
    @Published var adapterOutState: AdapterState?
    @Published var availableBalanceIn: Decimal?
    @Published var availableBalanceOut: Decimal?
    
    var isAvailableAmountIn: Bool {
        guard let availableBalanceIn, let amountIn else {
            return false
        }
        return availableBalanceIn >= amountIn
    }
    
    var amountIn: Decimal? {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: amountString)

            if amount != amountIn {
                amountString = amountIn?.description ?? ""
            }
        }
    }
    
    var amountOut: Decimal? {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: amountOutString)

            if amount != amountOut {
                amountOutString = amountOut?.description //?? ""
            }
        }
    }

    @Published var amountString: String = "" {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: amountString)

            guard amount != amountIn else {
                return
            }
            amountIn = amount
            amountOut = amount
        }
    }

    @Published var amountOutString: String? {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: amountOutString)

            guard amount != amountOut else {
                return
            }
            amountOut = amount
        }
    }
    
    init(tokenIn: Token, tokenOut: Token) {
        currency = currencyManager.baseCurrency
        defer {
            internalTokenIn = tokenIn
            internalTokenOut = tokenOut
        }

        currencyManager.$baseCurrency.sink { [weak self] in self?.currency = $0 }.store(in: &cancellables)
    }
}

extension Safe4SwapViewModel {
    func interchange() {

        let internalTokenIn = internalTokenIn
        self.internalTokenIn = internalTokenOut
        internalTokenOut = internalTokenIn
        
        let currentAmountOut = amountIn
        amountIn = currentAmountOut
        self.amountOut = amountIn
    }

    func setAmountIn(percent: Int) {
        guard let tokenIn, let availableBalanceIn else {
            return
        }

        amountIn = (availableBalanceIn * Decimal(percent) / 100).rounded(decimal: tokenIn.decimals)
        amountOut = amountIn
    }

    func clearAmountIn() {
        amountIn = nil
        amountOut = nil
    }
    
    func transactionData() -> TransactionData? {
        guard isAvailableAmountIn, let amountIn else { return  nil }
        guard let sendToken = internalTokenIn, sendToken.blockchainType == .safe4 else { return  nil }
        let evmAmount = validEvmAmount(sendToken: sendToken, amount: amountIn)
        let swapContractAddress = Safe4ContractAddress.Safe4SwapContractAddress
        let toAddress = try! EvmKit.Address(hex: swapContractAddress)

        var input: Data?
        if sendToken.blockchainType == .safe4, internalTokenIn?.type == .native {
            input = Web3jUtils.getSafe4SwapSrcTransactionInput()
            guard let input else { return nil }
            let transactionData = TransactionData(to: toAddress, value: evmAmount, input: input)
            return transactionData
        }else {
            input = Web3jUtils.getSrcSwapSafe4TransactionInput(amount: evmAmount)
            guard let input else { return nil }
            let transactionData = TransactionData(to: toAddress, value: .zero, input: input)
            return transactionData
        }
    }

    private func validEvmAmount(sendToken: Token, amount: Decimal) -> BigUInt {
        let evmAmount = BigUInt(amount.hs.roundedString(decimal: sendToken.decimals))
        return evmAmount ?? 0
    }
    
    func updateScr20Balance(wallet: Wallet) {
        guard let adapter = Core.shared.adapterManager.adapter(for: wallet) else { return }
        adapter.start()
    }
}

extension Safe4SwapViewModel {
    struct SwapToken {
        let token: Token
        let balance: Decimal
    }
}
