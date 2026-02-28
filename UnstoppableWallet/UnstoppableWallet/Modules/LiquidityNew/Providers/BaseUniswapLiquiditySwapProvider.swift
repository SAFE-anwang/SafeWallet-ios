import EvmKit
import Foundation
import MarketKit
import SwiftUI
import UniswapKit

class BaseUniswapLiquiditySwapProvider: BaseEvmLiquiditySwapProvider {
    let marketKit = Core.shared.marketKit
    let evmSyncSourceManager = Core.shared.evmSyncSourceManager
    let evmFeeEstimator = EvmFeeEstimator()

    override func quote(token0: MarketKit.Token, token1: MarketKit.Token, amount0: Decimal) async throws -> ILiquiditySwapQuote {
        try await internalQuote(token0: token0, token1: token1, amount0: amount0)
    }

    override func confirmationQuote(token0: MarketKit.Token, token1: MarketKit.Token, amount0: Decimal, transactionSettings: TransactionSettings?) async throws -> ILiquiditySwapConfirmationQuote {
        let quote = try await internalQuote(token0: token0, token1: token1, amount0: amount0)

        let blockchainType = token0.blockchainType
        let gasPriceData = transactionSettings?.gasPriceData
        var txData: TransactionData?
        var evmFeeData: EvmFeeData?
        var transactionError: Error?

        if let evmKitWrapper = try evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper, let gasPriceData {
            do {
                let evmKit = evmKitWrapper.evmKit
                let transactionData = try await transactionData(receiveAddress: evmKit.receiveAddress, chain: evmKit.chain, trade: quote.trade, tradeOptions: quote.tradeOptions)
                txData = transactionData
                evmFeeData = try await evmFeeEstimator.estimateFee(evmKitWrapper: evmKitWrapper, transactionData: transactionData, gasPriceData: gasPriceData)
            } catch {
                transactionError = error
            }
        }

        return BaseUniswapLiquiditySwapConfirmationQuote(
            quote: quote,
            transactionData: txData,
            transactionError: transactionError,
            gasPrice: gasPriceData?.userDefined,
            evmFeeData: evmFeeData,
            nonce: transactionSettings?.nonce
        )
    }

    private func settingsView(token1: MarketKit.Token, onChangeSettings: @escaping () -> Void) -> AnyView {
        let view = ThemeNavigationStack {
            RecipientAndSlippageMultiSwapSettingsView(tokenOut: token1, storage: storage, slippageMode: .adjustable, onChangeSettings: onChangeSettings)
        }

        return AnyView(view)
    }

    override func settingsView(token0 _: MarketKit.Token, token1: MarketKit.Token, quote _: ILiquiditySwapQuote, onChangeSettings: @escaping () -> Void) -> AnyView {
        settingsView(token1: token1, onChangeSettings: onChangeSettings)
    }

    override func settingView(settingId: String, tokenOut: MarketKit.Token, onChangeSetting: @escaping () -> Void) -> AnyView {
        if settingId == MultiSwapMainField.slippageSettingId {
            return settingsView(token1: tokenOut, onChangeSettings: onChangeSetting)
        }

        return super.settingView(settingId: settingId, tokenOut: tokenOut, onChangeSetting: onChangeSetting)
    }

    override func swap(token0: MarketKit.Token, token1 _: MarketKit.Token, amount0 _: Decimal, quote: ILiquiditySwapConfirmationQuote) async throws {
        guard let quote = quote as? BaseUniswapLiquiditySwapConfirmationQuote else {
            throw SwapError.invalidQuote
        }

        guard let transactionData = quote.transactionData else {
            throw SwapError.noTransactionData
        }

        guard let gasPrice = quote.gasPrice else {
            throw SwapError.noGasPrice
        }

        guard let gasLimit = quote.evmFeeData?.surchargedGasLimit else {
            throw SwapError.noGasLimit
        }

        try await super.send(
            blockchainType: token0.blockchainType,
            transactionData: transactionData,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            nonce: quote.nonce
        )
    }

    func kitToken(chain _: Chain, token _: MarketKit.Token) throws -> UniswapKit.Token {
        fatalError("Must be implemented in subclass")
    }

    func trade(rpcSource _: RpcSource, chain _: Chain, token0 _: UniswapKit.Token, token1 _: UniswapKit.Token, amountIn _: Decimal, tradeOptions _: TradeOptions) async throws -> BaseUniswapLiquiditySwapQuote.Trade {
        fatalError("Must be implemented in subclass")
    }

    func transactionData(receiveAddress _: EvmKit.Address, chain _: Chain, trade _: BaseUniswapLiquiditySwapQuote.Trade, tradeOptions _: TradeOptions) async throws -> TransactionData {
        fatalError("Must be implemented in subclass")
    }

    private func internalQuote(token0: MarketKit.Token, token1: MarketKit.Token, amount0: Decimal) async throws -> BaseUniswapLiquiditySwapQuote {
        let blockchainType = token0.blockchainType
        let chain = try evmBlockchainManager.chain(blockchainType: blockchainType)

        let kittoken0 = try kitToken(chain: chain, token: token0)
        let kittoken1 = try kitToken(chain: chain, token: token1)

        guard let rpcSource = evmSyncSourceManager.httpSyncSource(blockchainType: blockchainType)?.rpcSource else {
            throw SwapError.noHttpRpcSource
        }

        let recipient = storage.recipient(blockchainType: blockchainType)
        let slippage: Decimal = storage.value(for: MultiSwapSettingStorage.LegacySetting.slippage) ?? MultiSwapSlippage.default

        let kitRecipient = try recipient.map { try EvmKit.Address(hex: $0.raw) }

        let tradeOptions = TradeOptions(
            allowedSlippage: slippage,
            ttl: TradeOptions.defaultTtl,
            recipient: kitRecipient,
            feeOnTransfer: false
        )

        let trade = try await trade(rpcSource: rpcSource, chain: chain, token0: kittoken0, token1: kittoken1, amountIn: amount0, tradeOptions: tradeOptions)

        return await BaseUniswapLiquiditySwapQuote(
            trade: trade,
            tradeOptions: tradeOptions,
            recipient: recipient,
            providerName: name,
            allowanceState: allowanceState(token: token0, amount: amount0),
        )
    }
}

extension BaseUniswapLiquiditySwapProvider {
    enum SwapError: Error {
        case invalidToken
        case noHttpRpcSource
        case invalidQuote
        case invalidTrade
        case noTransactionData
        case noGasPrice
        case noGasLimit
        case noEvmKitWrapper
    }

    enum PriceImpactLevel {
        case negligible
        case normal
        case warning
        case forbidden

        private static let normalPriceImpact: Decimal = 1
        private static let warningPriceImpact: Decimal = 5
        private static let forbiddenPriceImpact: Decimal = 20

        init(priceImpact: Decimal) {
            switch priceImpact {
            case 0 ..< Self.normalPriceImpact: self = .negligible
            case Self.normalPriceImpact ..< Self.warningPriceImpact: self = .normal
            case Self.warningPriceImpact ..< Self.forbiddenPriceImpact: self = .warning
            default: self = .forbidden
            }
        }

        var valueLevel: ValueLevel {
            switch self {
            case .warning: return .warning
            case .forbidden: return .error
            default: return .regular
            }
        }
    }
}

