import Combine
import Foundation
import MarketKit
import SwiftUI

protocol ILiquidityAddProvider {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var requireTerms: Bool { get }
    var syncPublisher: AnyPublisher<Void, Never>? { get }
    func supports(token0: Token, token1: Token) -> Bool
    func quote(token0: Token, token1: Token, amount0: Decimal) async throws -> LiquidityAddQuote
    func confirmationQuote(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) async throws -> LiquidityAddFinalQuote
    func otherSections(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) -> [SendDataSection]
    func preSwapView(step: MultiSwapPreSwapStep, token0: Token, token1: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView
    func preSwapView(step: MultiSwapPreSwapStep, tokenToApprove: Token, otherToken: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView
    func slippageSupported(token0: Token, token1: Token) -> Bool
}

extension ILiquidityAddProvider {
    var requireTerms: Bool {
        false
    }

    var syncPublisher: AnyPublisher<Void, Never>? {
        nil
    }

    func slippageSupported(token0: Token, token1: Token) -> Bool {
        true
    }
}
