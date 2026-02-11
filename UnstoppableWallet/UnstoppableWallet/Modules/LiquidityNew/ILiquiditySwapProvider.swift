import Foundation
import MarketKit
import SwiftUI

protocol ILiquiditySwapProvider {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    func supports(token0: Token, token1: Token) -> Bool
    func quote(token0: Token, token1: Token, amount0: Decimal) async throws -> ILiquiditySwapQuote
    func confirmationQuote(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) async throws -> ILiquiditySwapConfirmationQuote
    func otherSections(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) -> [SendDataSection]
    func settingsView(token0: Token, token1: Token, quote: ILiquiditySwapQuote, onChangeSettings: @escaping () -> Void) -> AnyView
    func settingView(settingId: String, tokenOut: Token, onChangeSetting: @escaping () -> Void) -> AnyView
    func preSwapView(step: MultiSwapPreSwapStep, token0: Token, token1: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView
    func swap(token0: Token, token1: Token, amount0: Decimal, quote: ILiquiditySwapConfirmationQuote) async throws
}
