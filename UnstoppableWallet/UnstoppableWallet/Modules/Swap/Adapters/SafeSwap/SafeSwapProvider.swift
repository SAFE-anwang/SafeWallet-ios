//import SafeSwapKit
//import RxSwift
//import EvmKit
//import Foundation
//import MarketKit
//
//class SafeSwapProvider {
//    private let swapKit: SafeSwapKit.Kit
//
//    init(swapKit: SafeSwapKit.Kit) {
//        self.swapKit = swapKit
//    }
//
//    private func safeSwapToken(token: MarketKit.Token) throws -> SafeSwapKit.Token {
//        switch token.type {
//        case .native: return swapKit.etherToken
//        case let .eip20(address): return swapKit.token(contractAddress: try EvmKit.Address(hex: address), decimals: token.decimals)
//        default: throw TokenError.unsupportedToken
//        }
//    }
//
//}
//
//extension SafeSwapProvider {
//
//    var routerAddress: EvmKit.Address {
//        swapKit.routerAddress
//    }
//
//    var wethAddress: EvmKit.Address {
//        swapKit.etherToken.address
//    }
//
//    func swapDataSingle(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Single<SwapData> {
//        do {
//            let safeSwapTokenIn = try safeSwapToken(token: tokenIn)
//            let safeSwapTokenOut = try safeSwapToken(token: tokenOut)
//
//            return swapKit.swapDataSingle(tokenIn: safeSwapTokenIn, tokenOut: safeSwapTokenOut)
//        } catch {
//            return Single.error(error)
//        }
//    }
//
//    func tradeData(swapData: SwapData, amount: Decimal, tradeType: TradeType, tradeOptions: TradeOptions) throws -> TradeData {
//        switch tradeType {
//        case .exactIn:
//            return try swapKit.bestTradeExactIn(swapData: swapData, amountIn: amount, options: tradeOptions)
//        case .exactOut:
//            return try swapKit.bestTradeExactOut(swapData: swapData, amountOut: amount, options: tradeOptions)
//        }
//    }
//
//    func transactionData(tradeData: TradeData) throws -> TransactionData {
//        try swapKit.transactionData(tradeData: tradeData)
//    }
//
//}
//
//extension SafeSwapProvider {
//
//    enum TokenError: Error {
//        case unsupportedToken
//    }
//
//}
//

import Foundation
import SafeSwapKit
import RxSwift
import EvmKit
import Foundation
import MarketKit
import BigInt
import HsExtensions

class SafeSwapProvider {
    private let swapKit: SafeSwapKit.Kit

    init(swapKit: SafeSwapKit.Kit) {
        self.swapKit = swapKit
    }

    private func units(amount: Decimal, token: MarketKit.Token) -> BigUInt? {
        let amountUnitString = (amount * pow(10, token.decimals)).hs.roundedString(decimal: 0)
        return BigUInt(amountUnitString)
    }

    private func address(token: MarketKit.Token) throws -> EvmKit.Address {
        switch token.type {
        case .native: return try EvmKit.Address(hex: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        case .eip20(let address): return try EvmKit.Address(hex: address)
        default: throw SwapError.invalidAddress
        }
    }

}

extension SafeSwapProvider {

    var routerAddress: EvmKit.Address {
        swapKit.routerAddress
    }

    func quoteSingle(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token, amount: Decimal) -> Single<SafeSwapKit.Quote> {
        guard let amountUnits = units(amount: amount, token: tokenIn) else {
            return Single.error(SwapError.insufficientAmount)
        }

        do {
            let addressFrom = try address(token: tokenIn)
            let addressTo = try address(token: tokenOut)

            return swapKit.quoteSingle(
                    fromToken: addressFrom,
                    toToken: addressTo,
                    amount: amountUnits,
                    protocols: nil,
                    gasPrice: nil,
                    complexityLevel: nil,
                    connectorTokens: nil,
                    gasLimit: nil,
                    mainRouteParts: nil,
                    parts: nil
            )
        } catch {
            return Single.error(error)
        }
    }

    func swapSingle(tokenFrom: MarketKit.Token, tokenTo: MarketKit.Token, amount: Decimal, recipient: EvmKit.Address?, slippage: Decimal, gasPrice: GasPrice?) -> Single<SafeSwapKit.Swap> {
        guard let amountUnits = units(amount: amount, token: tokenFrom) else {
            return Single.error(SwapError.insufficientAmount)
        }

        do {
            let addressFrom = try address(token: tokenFrom)
            let addressTo = try address(token: tokenTo)

            return swapKit.swapSingle(
                    fromToken: addressFrom,
                    toToken: addressTo,
                    amount: amountUnits,
                    slippage: slippage,
                    protocols: nil,
                    recipient: recipient,
                    gasPrice: gasPrice,
                    burnChi: nil,
                    complexityLevel: nil,
                    connectorTokens: nil,
                    allowPartialFill: nil,
                    gasLimit: nil,
                    mainRouteParts: nil,
                    parts: nil
            )
        } catch {
            return Single.error(error)
        }

    }

}

extension SafeSwapProvider {

    enum SwapError: Error {
        case invalidAddress
        case insufficientAmount
    }

}
