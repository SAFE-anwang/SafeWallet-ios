import Combine
import EvmKit
import Foundation
import MarketKit
import SwiftUI

class BaseEvmLiquidityAddProvider: ILiquidityAddProvider {
    private let adapterManager = Core.shared.adapterManager
    private let localStorage = Core.shared.localStorage
    let evmBlockchainManager = Core.shared.evmBlockchainManager
    let storage: MultiSwapSettingStorage
    private let allowanceHelper = LiquidityAddAllowanceHelper()

    @Published private var useMevProtection: Bool = false

    init(storage: MultiSwapSettingStorage) {
        self.storage = storage
    }

    var id: String { fatalError("Must be implemented in subclass") }
    var name: String { fatalError("Must be implemented in subclass") }
    var icon: String { fatalError("Must be implemented in subclass") }

    func supports(token0: Token, token1: Token) -> Bool {
        fatalError("Must be implemented in subclass")
    }

    func quote(token0: Token, token1: Token, amount0: Decimal) async throws -> LiquidityAddQuote {
        fatalError("Must be implemented in subclass")
    }

    func confirmationQuote(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) async throws -> LiquidityAddFinalQuote {
        fatalError("Must be implemented in subclass")
    }

    func confirmationQuote(token0: Token, token1: Token, amount0: Decimal, amount1 _: Decimal?, transactionSettings: TransactionSettings?) async throws -> LiquidityAddFinalQuote {
        try await confirmationQuote(token0: token0, token1: token1, amount0: amount0, transactionSettings: transactionSettings)
    }

    func otherSections(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) -> [SendDataSection] {
        useMevProtection = false
        return []
    }

    func preSwapView(step: MultiSwapPreSwapStep, token0: Token, token1: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView {
        allowanceHelper.preSwapView(step: step, token: token0, amount: amount, isPresented: isPresented, onSuccess: onSuccess)
    }
    
    func preSwapView(step: MultiSwapPreSwapStep, tokenToApprove: Token, otherToken: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView {
        allowanceHelper.preSwapView(step: step, token: tokenToApprove, amount: amount, isPresented: isPresented, onSuccess: onSuccess)
    }

    func swap(token0: Token, token1: Token, amount0: Decimal, quote: LiquidityAddFinalQuote) async throws {
        fatalError("Must be implemented in subclass")
    }

    func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        fatalError("Must be implemented in subclass")
    }

    func allowanceState(token: Token, amount: Decimal) async -> LiquidityAddAllowanceHelper.AllowanceState {
        do {
            let chain = try evmBlockchainManager.chain(blockchainType: token.blockchainType)
            let spenderAddress = try spenderAddress(chain: chain)

            return await allowanceHelper.allowanceState(spenderAddress: .init(raw: spenderAddress.eip55), token: token, amount: amount)
        } catch {
            return .unknown
        }
    }

    func send(blockchainType: BlockchainType, transactionData: TransactionData, gasPrice: GasPrice, gasLimit: Int, nonce: Int? = nil) async throws {
        guard let evmKitWrapper = try evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
            throw SwapError.noEvmKitWrapper
        }

        _ = try await evmKitWrapper.send(
            transactionData: transactionData,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            privateSend: useMevProtection,
            nonce: nonce
        )
    }
}

extension BaseEvmLiquidityAddProvider {
    enum SwapError: Error {
        case noEvmKitWrapper
        case invalidQuote
        case noTransactionData
        case noGasPrice
        case noGasLimit
    }

    static func validateBalance(evmKitWrapper: EvmKitWrapper, transactionData: TransactionData, evmFeeData: EvmFeeData, gasPriceData: GasPriceData) throws {
        let evmBalance = evmKitWrapper.evmKit.accountState?.balance ?? 0
        let txAmount = transactionData.value
        let feeAmount = evmFeeData.totalFee(gasPrice: gasPriceData.userDefined)

        if txAmount + feeAmount > evmBalance {
            throw AppError.ethereum(reason: .insufficientBalanceWithFee)
        }
    }
}
