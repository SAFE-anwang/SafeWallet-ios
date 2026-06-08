import Combine
import Foundation
import MarketKit
import RxSwift
import SwiftUI

protocol IMultiSwapProvider {
    var id: String { get }
    var name: String { get }
    var type: SwapProviderType { get }
    var requireTerms: Bool { get }
    var icon: String { get }
    var syncPublisher: AnyPublisher<Void, Never>? { get }
    func slippageSupported(tokenIn: Token, tokenOut: Token) -> Bool
    func supports(tokenIn: Token, tokenOut: Token) -> Bool
    func quote(tokenIn: Token, tokenOut: Token, amountIn: Decimal) async throws -> MultiSwapQuote
    func confirmationQuote(tokenIn: Token, tokenOut: Token, amountIn: Decimal, slippage: Decimal, recipient: String?, transactionSettings: TransactionSettings?) async throws -> SwapFinalQuote
    func validateTrustedProvider(tokenIn: Token, amountIn: Decimal) async throws -> Bool?
    func preSwapView(step: MultiSwapPreSwapStep, tokenIn: Token, tokenOut: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView
    func track(swap: Swap) async throws -> Swap
}

extension IMultiSwapProvider {
    var requireTerms: Bool {
        false
    }

    var syncPublisher: AnyPublisher<Void, Never>? {
        nil
    }

    func slippageSupported(tokenIn _: Token, tokenOut _: Token) -> Bool {
        true
    }

    func validateTrustedProvider(tokenIn _: Token, amountIn _: Decimal) async -> Bool? {
        if let result = Core.instance?.localStorage.debuggingAmlCheckResult {
            return result == .dirty ? false : nil
        }
        return true
    }

    func localTrackedSwap(swap: Swap, token: Token) async throws -> Swap? {
        guard let txHash = swap.txHash,
              let account = Core.shared.accountManager.account(id: swap.accountId)
        else {
            return nil
        }

        let wallet = Wallet(token: token, account: account)

        guard let adapter = Core.shared.transactionAdapterManager.adapter(for: wallet.transactionSource) else {
            return nil
        }

        let records = try await transactionRecords(adapter: adapter, token: token, limit: 100)

        guard let record = records.first(where: { $0.transactionHash.caseInsensitiveCompare(txHash) == .orderedSame }) else {
            return nil
        }

        var updatedSwap = swap
        updatedSwap.status = swapStatus(from: record.status(lastBlockHeight: adapter.lastBlockInfo?.height))
        return updatedSwap
    }

    private func transactionRecords(adapter: ITransactionsAdapter, token: Token, limit: Int) async throws -> [TransactionRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let disposable = adapter.transactionsSingle(
                paginationData: nil,
                token: token,
                filter: .all,
                address: nil,
                limit: limit
            )
            .subscribe(
                onSuccess: { records in
                    continuation.resume(returning: records)
                },
                onError: { error in
                    continuation.resume(throwing: error)
                }
            )

            _ = disposable
        }
    }

    private func swapStatus(from transactionStatus: TransactionStatus) -> Swap.Status {
        switch transactionStatus {
        case .failed: return .failed
        case .pending: return .pending
        case .processing: return .swapping
        case .completed: return .completed
        }
    }
}

enum SwapProviderType: String, CaseIterable, Identifiable {
    case auto
    case flexible
    case controlled
    case preCheck

    var title: String {
        rawValue.capitalized(with: .autoupdatingCurrent)
    }

    var icon: String {
        switch self {
        case .auto: return "shield_check_filled"
        case .flexible: return "thumbsup"
        case .controlled: return "warning_filled"
        case .preCheck: return "radar"
        }
    }

    var сolorStyle: ColorStyle {
        switch self {
        case .auto: return .green
        case .flexible: return .blue
        case .controlled: return .yellow
        case .preCheck: return .primary
        }
    }

    var id: String {
        rawValue
    }

    @ViewBuilder func body() -> some View {
        HStack(spacing: .margin4) {
            ThemeImage(icon, size: .iconSize16, colorStyle: сolorStyle)
            ThemeText(title, style: .captionSB, colorStyle: сolorStyle)
        }
    }
}
