import Combine
import Foundation
import HsExtensions
import MarketKit
import EvmKit
import BigInt
import Web3Core
import web3swift
import Combine
import Foundation
import HsExtensions
import MarketKit
/*
class Safe4SwapConfirmationViewModel: ObservableObject {
    let quoteExpirationDuration: Int = 10
    let evmBlockchainManager = Core.shared.evmBlockchainManager
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    
    private var quoteTask: AnyTask?
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    let tokenIn: Token
    let tokenOut: Token
    let amountIn: Decimal
    let currency: Currency
    let feeToken: Token?
    let transactionData: TransactionData
    
    @Published var rateIn: Decimal?
    @Published var rateOut: Decimal?
    @Published var feeTokenRate: Decimal?
    @Published var amountData: AmountData?
    @Published var state: State = .quoting {
        didSet {

            timer?.cancel()
            if let quote = state.quote {
                quoteTimeLeft = quoteExpirationDuration

                timer = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        self?.handleTimerTick()
                    }
            }
        }
    }

    @Published var quoteTimeLeft: Int = 0
    private var priceFlipped = false

    @Published var swapping = false

    var recipient: String {
        transactionData.to.hex
    }
    
    let errorSubject = PassthroughSubject<String, Never>()

    init(transactionData: TransactionData, tokenIn: Token, tokenOut: Token, amountIn: Decimal) {
        self.transactionData = transactionData
        self.tokenIn = tokenIn
        self.tokenOut = tokenOut
        self.amountIn = amountIn
        currency = currencyManager.baseCurrency
        feeToken = try? marketKit.token(query: TokenQuery(blockchainType: tokenIn.blockchainType, tokenType: .native))

        if let feeToken {
            feeTokenRate = marketKit.coinPrice(coinUid: feeToken.coin.uid, currencyCode: currency.code)?.value
        }
        
        syncQuote()
    }

    private func handleTimerTick() {
        quoteTimeLeft -= 1

        if quoteTimeLeft == 0 {
            timer?.cancel()
        }
    }

    @MainActor private func set(swapping: Bool) {
        self.swapping = swapping
    }
}

extension Safe4SwapConfirmationViewModel {
    func syncQuote() {
        quoteTask = nil
        if !state.isQuoting {
            state = .quoting
        }
        quoteTask = Task { [weak self, transactionData, tokenIn, evmBlockchainManager] in
            var state: State
            do {
                let gasLimit = Safe4SwapModule.gasLimit

                guard let evmKit = try? evmBlockchainManager.evmKitManager(blockchainType: tokenIn.blockchainType).evmKitWrapper?.evmKit else { throw SwapError.noEvmKitWrapper }
                let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKit)
                async let gasPrice = try gasPriceProvider.gasPrice()
                async let nonce = try evmKit.nonce(defaultBlockParameter: .pending)
                
                let data = try await SendData(transactionData: transactionData, evmFeeData: EvmFeeData(gasLimit: gasLimit, surchargedGasLimit: gasLimit), gasPrice: gasPrice, gasLimit: gasLimit, nonce: nonce)
                self?.syncAmountData(data: data)
                state = .success(data)

            } catch {
                state = .failed(error: error)
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self, state] in
                    self?.state = state
                }
            }
        }
        .erased()
    }
    
    private func validEvmAmount(sendToken: MarketKit.Token, amount: Decimal) -> BigUInt {
        let evmAmount = BigUInt(amount.hs.roundedString(decimal: sendToken.decimals))
        return evmAmount ?? 0
    }
    
    func flipPrice() {
        priceFlipped.toggle()
    }

    func swap() async throws {
        do {
            guard let quote = state.quote else {
                throw SwapError.noQuote
            }

            await set(swapping: true)

            guard let evmKitWrapper = try? evmBlockchainManager.evmKitManager(blockchainType: tokenIn.blockchainType).evmKitWrapper else {
                throw SwapError.noEvmKitWrapper
            }

            _ = try await evmKitWrapper.send(
                transactionData: quote.transactionData,
                gasPrice: quote.gasPrice,
                gasLimit: quote.gasLimit,
                privateSend: false,
                nonce: quote.nonce
            )
        } catch {
            await set(swapping: false)
            errorSubject.send(error.smartDescription)
            throw error
        }
    }
    
    func syncAmountData(data: SendData) {
        let evmFeeData = EvmFeeData(gasLimit: Safe4SwapModule.gasLimit, surchargedGasLimit: Safe4SwapModule.gasLimit)
        guard let feeToken, let feeTokenRate else { return amountData = nil }
        amountData = evmFeeData.totalAmountData(gasPrice: data.gasPrice , feeToken: feeToken, currency: currency, feeTokenRate: feeTokenRate)
    }
}

extension Safe4SwapConfirmationViewModel {
    enum State {
        case quoting
        case success(SendData)
        case failed(error: Error)

        var quote: SendData? {
            switch self {
            case let .success(quote): return quote
            default: return nil
            }
        }

        var isQuoting: Bool {
            switch self {
            case .quoting: return true
            default: return false
            }
        }
    }

    enum SwapError: Error {
        case noQuote
        case noTransactionData
        case noGasPrice
        case noGasLimit
        case noEvmKitWrapper
        case noSafe4
    }
    
    struct SendData {
        let transactionData: TransactionData
        let evmFeeData: EvmFeeData
        let gasPrice: GasPrice
        let gasLimit: Int
        let nonce: Int
    }
}

*/
