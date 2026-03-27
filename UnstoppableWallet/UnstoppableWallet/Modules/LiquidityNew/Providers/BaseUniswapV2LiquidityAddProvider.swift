import EvmKit
import BigInt
import Foundation
import MarketKit
import UniswapKit

class BaseUniswapV2LiquidityAddProvider: BaseUniswapLiquidityAddProvider {
    let kit: UniswapKit.Kit

    init(kit: UniswapKit.Kit, storage: MultiSwapSettingStorage) {
        self.kit = kit

        super.init(storage: storage)
    }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        try kit.routerAddress(chain: chain)
    }

    override func kitToken(chain: Chain, token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try kit.etherToken(chain: chain)
        case let .eip20(address): return try kit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw SwapError.invalidToken
        }
    }

    override func trade(rpcSource: RpcSource, chain: Chain, token0 tokenIn: UniswapKit.Token, token1 tokenOut: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> UniswapLiquidityAddQuote.Trade {
        let swapData = try await kit.swapData(rpcSource: rpcSource, chain: chain, tokenIn: tokenIn, tokenOut: tokenOut)
        let tradeData = try kit.bestTradeExactIn(swapData: swapData, amountIn: amountIn, options: tradeOptions)
        return .v2(tradeData: tradeData)
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: UniswapLiquidityAddQuote.Trade, tradeOptions _: TradeOptions) async throws -> TransactionData {
        guard case let .v2(tradeData) = trade else {
            throw SwapError.invalidTrade
        }
        return try kit.transactionLiquidityData(tradeData: tradeData, type: .add, chain: chain, recipient: receiveAddress)
    }

    override func confirmationQuote(token0: MarketKit.Token, token1: MarketKit.Token, amount0: Decimal, amount1: Decimal?, transactionSettings: TransactionSettings?) async throws -> LiquidityAddFinalQuote {
        guard kit.isSafeSwap,
              let amount1,
              amount1 > 0
        else {
            return try await super.confirmationQuote(token0: token0, token1: token1, amount0: amount0, transactionSettings: transactionSettings)
        }

        return try await manualConfirmationQuote(
            token0: token0,
            token1: token1,
            amount0: amount0,
            amount1: amount1,
            transactionSettings: transactionSettings
        )
    }

    private func manualConfirmationQuote(token0: MarketKit.Token, token1: MarketKit.Token, amount0: Decimal, amount1: Decimal, transactionSettings: TransactionSettings?) async throws -> LiquidityAddFinalQuote {
        let blockchainType = token0.blockchainType
        let chain = try evmBlockchainManager.chain(blockchainType: blockchainType)
        let slippage = storage.value(for: MultiSwapSettingStorage.LegacySetting.slippage) ?? MultiSwapSlippage.default

        var txData: TransactionData?
        var evmFeeData: EvmFeeData?
        var transactionError: Error?
        var usedGasPrice: GasPrice?

        do {
            guard let evmKitWrapper = try evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
                throw SwapError.noEvmKitWrapper
            }

            let evmKit = evmKitWrapper.evmKit
            let transactionData = try manualAddLiquidityTransactionData(
                token0: token0,
                token1: token1,
                amount0: amount0,
                amount1: amount1,
                receiveAddress: evmKit.receiveAddress,
                chain: chain
            )
            txData = transactionData

            let gasPriceData = try await resolvedGasPriceData(transactionSettings: transactionSettings, chain: chain, blockchainType: blockchainType)
            usedGasPrice = gasPriceData.userDefined

            do {
                evmFeeData = try await evmFeeEstimator.estimateFee(
                    evmKitWrapper: evmKitWrapper,
                    transactionData: transactionData,
                    gasPriceData: gasPriceData
                )
            } catch {
                // Some nodes fail to estimate gas for addLiquidity on a non-existing pool.
                // Use a safe fallback gas limit so user can still proceed.
                evmFeeData = try await evmFeeEstimator.estimateFee(
                    evmKitWrapper: evmKitWrapper,
                    transactionData: transactionData,
                    gasPriceData: gasPriceData,
                    predefinedGasLimit: fallbackGasLimit(token0: token0, token1: token1)
                )
            }
        } catch {
            transactionError = error
        }

        return EvmLiquidityAddFinalQuote(
            expectedBuyAmount: amount1,
            transactionData: txData,
            transactionError: transactionError,
            slippage: slippage,
            recipient: nil,
            gasPrice: usedGasPrice,
            evmFeeData: evmFeeData,
            nonce: transactionSettings?.nonce
        )
    }

    private func resolvedGasPriceData(transactionSettings: TransactionSettings?, chain: Chain, blockchainType: BlockchainType) async throws -> GasPriceData {
        if let gasPriceData = transactionSettings?.gasPriceData {
            return gasPriceData
        }

        guard let rpcSource = evmSyncSourceManager.httpSyncSource(blockchainType: blockchainType)?.rpcSource else {
            throw SwapError.noHttpRpcSource
        }

        let recommendedGasPrice: GasPrice
        if chain.isEIP1559Supported {
            recommendedGasPrice = try await EIP1559GasPriceProvider.gasPrice(networkManager: Core.shared.networkManager, rpcSource: rpcSource)
        } else {
            recommendedGasPrice = try await LegacyGasPriceProvider.gasPrice(networkManager: Core.shared.networkManager, rpcSource: rpcSource)
        }

        return GasPriceData(recommended: recommendedGasPrice, userDefined: recommendedGasPrice)
    }

    private func fallbackGasLimit(token0: MarketKit.Token, token1: MarketKit.Token) -> Int {
        let hasNativeToken: Bool = {
            switch (token0.type, token1.type) {
            case (.native, _), (_, .native): return true
            default: return false
            }
        }()
        return hasNativeToken ? 450_000 : 500_000
    }

    private func manualAddLiquidityTransactionData(
        token0: MarketKit.Token,
        token1: MarketKit.Token,
        amount0: Decimal,
        amount1: Decimal,
        receiveAddress: EvmKit.Address,
        chain: Chain
    ) throws -> TransactionData {
        guard let amount0Raw = token0.rawAmount(amount0),
              let amount1Raw = token1.rawAmount(amount1)
        else {
            throw SwapError.invalidQuote
        }

        // For first-time pool creation there are no reserves to constrain ratio;
        // keep mins at zero to avoid false reverts from strict min checks.
        let amount0Min: BigUInt = .zero
        let amount1Min: BigUInt = .zero
        let deadline = Constants.getDeadLine()
        let routerAddress = try spenderAddress(chain: chain)

        switch token0.type {
        case .native:
            guard case let .eip20(address) = token1.type else {
                throw SwapError.invalidToken
            }
            let method = AddLiquidityEthMethod(
                token: try EvmKit.Address(hex: address),
                amountTokenDesired: amount1Raw,
                amountTokenMin: amount1Min,
                amountEthMin: amount0Min,
                to: receiveAddress,
                deadline: deadline
            )
            return TransactionData(to: routerAddress, value: amount0Raw, input: method.encodedABI())
        case let .eip20(address0):
            let token0Address = try EvmKit.Address(hex: address0)
            switch token1.type {
            case .native:
                let method = AddLiquidityEthMethod(
                    token: token0Address,
                    amountTokenDesired: amount0Raw,
                    amountTokenMin: amount0Min,
                    amountEthMin: amount1Min,
                    to: receiveAddress,
                    deadline: deadline
                )
                return TransactionData(to: routerAddress, value: amount1Raw, input: method.encodedABI())
            case let .eip20(address1):
                let method = AddLiquidityMethod(
                    tokenA: token0Address,
                    tokenB: try EvmKit.Address(hex: address1),
                    amountADesired: amount0Raw,
                    amountBDesired: amount1Raw,
                    amountAMin: amount0Min,
                    amountBMin: amount1Min,
                    to: receiveAddress,
                    deadline: deadline
                )
                return TransactionData(to: routerAddress, value: .zero, input: method.encodedABI())
            default:
                throw SwapError.invalidToken
            }
        default:
            throw SwapError.invalidToken
        }
    }

}
