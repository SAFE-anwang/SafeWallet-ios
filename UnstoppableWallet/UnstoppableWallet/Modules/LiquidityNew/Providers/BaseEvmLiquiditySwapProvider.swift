import Foundation
import Combine
import EvmKit
import Foundation
import MarketKit
import SwiftUI

class BaseEvmLiquiditySwapProvider: ILiquiditySwapProvider {
    private let adapterManager = Core.shared.adapterManager
    private let localStorage = Core.shared.localStorage
    let evmBlockchainManager = Core.shared.evmBlockchainManager
    let storage: MultiSwapSettingStorage
    private let allowanceHelper = LiquiditySwapAllowanceHelper()

    @Published private var useMevProtection: Bool = false

    init(storage: MultiSwapSettingStorage) {
        self.storage = storage
    }

    var id: String {
        fatalError("Must be implemented in subclass")
    }

    var name: String {
        fatalError("Must be implemented in subclass")
    }

    var icon: String {
        fatalError("Must be implemented in subclass")
    }

    func supports(token0 _: Token, token1 _: Token) -> Bool {
        fatalError("Must be implemented in subclass")
    }

    func quote(token0 _: Token, token1 _: Token, amount0 _: Decimal) async throws -> ILiquiditySwapQuote {
        fatalError("Must be implemented in subclass")
    }

    func confirmationQuote(token0 _: Token, token1 _: Token, amount0 _: Decimal, transactionSettings _: TransactionSettings?) async throws -> ILiquiditySwapConfirmationQuote {
        fatalError("Must be implemented in subclass")
    }

    func otherSections(token0: Token, token1 _: Token, amount0 _: Decimal, transactionSettings _: TransactionSettings?) -> [SendDataSection] {
        useMevProtection = false
        return []
    }

    func settingsView(token0 _: Token, token1 _: Token, quote _: ILiquiditySwapQuote, onChangeSettings _: @escaping () -> Void) -> AnyView {
        fatalError("settingsView(tokenIn:tokenOut:onChangeSettings:) has not been implemented")
    }

    func settingView(settingId _: String, tokenOut _: Token, onChangeSetting _: @escaping () -> Void) -> AnyView {
        fatalError("settingView(settingId:) has not been implemented")
    }

    func preSwapView(step: MultiSwapPreSwapStep, token0: Token, token1 _: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView {
        allowanceHelper.preSwapView(step: step, tokenIn: token0, amount: amount, isPresented: isPresented, onSuccess: onSuccess)
    }

    func swap(token0 _: Token, token1 _: Token, amount0 _: Decimal, quote _: ILiquiditySwapConfirmationQuote) async throws {
        fatalError("Must be implemented in subclass")
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

    func spenderAddress(chain _: Chain) throws -> EvmKit.Address {
        fatalError("Must be implemented in subclass")
    }

    func allowanceState(token: Token, amount: Decimal) async -> LiquiditySwapAllowanceHelper.AllowanceState {
        do {
            let chain = try evmBlockchainManager.chain(blockchainType: token.blockchainType)
            let spenderAddress = try spenderAddress(chain: chain)

            return await allowanceHelper.allowanceState(spenderAddress: .init(raw: spenderAddress.eip55), token: token, amount: amount)
        } catch {
            return .unknown
        }
    }
}

extension BaseEvmLiquiditySwapProvider {
    enum SwapError: Error {
        case noEvmKitWrapper
    }
}
