import Foundation
import MarketKit
import Testing
@testable import WalletCore

@MainActor
struct LiquidityAddRefreshTests {
    @Test func failedAllowanceReadDoesNotOfferApproval() async throws {
        let state = await failedAllowance(token: token(index: 1))
        guard case .unknown = state else {
            Issue.record("An RPC error must not be interpreted as insufficient allowance")
            return
        }
        let button = try #require(state.customButtonState)
        #expect(button.disabled)
        #expect(button.preSwapStep == nil)
    }

    @Test(arguments: [0, 1])
    func submittedApprovalSurvivesFailedReadsAndRecovers(index: Int) async throws {
        let token0 = token(index: 1)
        let token1 = token(index: 2)
        let submittedToken = index == 0 ? token0 : token1
        let responses = ApprovalQuoteRequests(token0: token0, token1: token1)
        let provider = RefreshTestProvider(quote: { await responses.quote() })
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await responses.completeAll() }
        }
        try #require(await waitUntil { viewModel.approvalButtons.count == 2 })
        let step = try #require(viewModel.approvalButtons[index].state.preSwapStep)
        viewModel.onAllowanceSubmitted(token: submittedToken, providerId: provider.id, step: step)
        try #require(await waitUntil { await responses.count == 2 })

        let failedState = await failedAllowance(token: submittedToken)
        let pendingState = LiquidityAddAllowanceHelper.AllowanceState.pendingAllowance(appValue: AppValue(token: submittedToken, value: 1))
        // A timeout before AND after observing the pending transaction must
        // preserve progress. Each response uses the real helper's error result.
        for (offset, state) in [failedState, pendingState, failedState].enumerated() {
            let requestId = offset + 2
            await responses.complete(requestId,
                state0: index == 0 ? state : insufficientAllowance(token: token0),
                state1: index == 1 ? state : insufficientAllowance(token: token1))
            try #require(await waitUntil {
                guard let quote = viewModel.currentQuote?.quote as? EvmLiquidityAddQuote else { return false }
                let publishedState = index == 0 ? quote.allowanceState0 : quote.allowanceState1
                return publishedState.customButtonState?.title == state.customButtonState?.title
            })
            let button = try #require(viewModel.approvalButtons.first { $0.token == submittedToken })
            #expect(button.state.title == "swap.approving_button".localized)
            #expect(button.state.disabled)
            #expect(button.state.showProgress)
            #expect(button.state.preSwapStep == nil)
            #expect(!viewModel.approvalButtons[1 - index].state.disabled)

            viewModel.refreshAfterPreSwap()
            try #require(await waitUntil { await responses.count == requestId + 1 })
        }

        await responses.complete(5, state0: .allowed, state1: .allowed)
        try #require(await waitUntil { viewModel.approvalButtons.isEmpty })
        #expect(viewModel.approvalButtonState(token: submittedToken, providerId: provider.id, fallback: nil) == nil)
    }

    @Test(arguments: [0, 1])
    func manualSubmittedApprovalSurvivesFailedReadAndRecovers(index: Int) async throws {
        let requests = AllowanceRequests()
        let provider = RefreshTestProvider(
            quote: { throw TestError.noPool },
            allowance: { token, amount in await requests.request(token: token, amount: amount) }
        )
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await requests.completeAll() }
        }
        try #require(await waitUntil { viewModel.isSafeSwapManualAmountOutMode })
        viewModel.manualAmountOutString = "1"
        try #require(await waitUntil { await requests.count == 2 })
        await requests.completeAll(state: insufficientAllowance(token: token(index: 1)))
        try #require(await waitUntil { viewModel.approvalButtons.allSatisfy { $0.state.preSwapStep != nil } })
        let button = viewModel.approvalButtons[index]
        let step = try #require(button.state.preSwapStep)
        viewModel.onAllowanceSubmitted(token: button.token, providerId: provider.id, step: step)
        try #require(await waitUntil { await requests.count == 4 })

        await requests.completeAll(state: await failedAllowance(token: button.token))
        // The other token's error button proves the failed result was published.
        try #require(await waitUntil { viewModel.approvalButtons[1 - index].state.title == "swap.allowance_error".localized })
        let pending = viewModel.approvalButtons[index].state
        #expect(pending.title == "swap.approving_button".localized)
        #expect(pending.disabled)
        #expect(pending.showProgress)
        #expect(pending.preSwapStep == nil)

        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await requests.count >= 6 })
        await requests.completeAll(state: insufficientAllowance(token: button.token))
        // A successful read of an insufficient allowance must allow retrying.
        try #require(await waitUntil { viewModel.approvalButtons.allSatisfy { !$0.state.disabled && $0.state.preSwapStep != nil } })
        #expect(viewModel.approvalButtonState(token: button.token, providerId: provider.id, fallback: nil) == nil)
    }

    private func failedAllowance(token: Token) async -> LiquidityAddAllowanceHelper.AllowanceState {
        let helper = LiquidityAddAllowanceHelper { _ in FailingAllowanceAdapter() }
        return await helper.allowanceState(spenderAddress: Address(raw: "spender"), token: token, amount: 1)
    }

    @Test func submittedTokenImmediatelyShowsProgressUntilFreshAllowanceArrives() async throws {
        let token0 = token(index: 1)
        let token1 = token(index: 2)
        let responses = ApprovalQuoteRequests(token0: token0, token1: token1)
        let provider = RefreshTestProvider(quote: { await responses.quote() })
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await responses.completeAll() }
        }
        try #require(await waitUntil { viewModel.approvalButtons.count == 2 })
        let firstStep = try #require(viewModel.approvalButtons[0].state.preSwapStep)

        viewModel.onAllowanceSubmitted(token: token0, providerId: provider.id, step: firstStep)
        let submittingFirst = viewModel.approvalButtons
        #expect(submittingFirst[0].state.title == "swap.approving_button".localized)
        #expect(submittingFirst[0].state.disabled)
        #expect(submittingFirst[0].state.showProgress)
        #expect(submittingFirst[0].state.preSwapStep == nil)
        #expect(!submittingFirst[1].state.disabled)
        #expect(!submittingFirst[1].state.showProgress)
        #expect(viewModel.approvalButtonState(token: token0, providerId: "another-router", fallback: nil) == nil)

        // Dismissing the sheet must preserve the state during the RPC wait.
        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await responses.count == 2 })
        #expect(viewModel.approvalButtons[0].state.showProgress)
        await responses.complete(2, state0: .allowed, state1: insufficientAllowance(token: token1))
        try #require(await waitUntil { viewModel.approvalButtons.count == 1 })
        let secondButton = try #require(viewModel.approvalButtons.first)
        #expect(secondButton.token == token1)
        let secondStep = try #require(secondButton.state.preSwapStep)

        viewModel.onAllowanceSubmitted(token: token1, providerId: provider.id, step: secondStep)
        #expect(viewModel.approvalButtons[0].state.showProgress)
        #expect(viewModel.approvalButtons[0].state.disabled)
        try #require(await waitUntil { await responses.count == 3 })
        await responses.complete(3, state0: .allowed, state1: .pendingAllowance(appValue: AppValue(token: token1, value: 1)))
        try #require(await waitUntil { viewModel.currentQuote?.quote.customButtonState1?.showProgress == true })
        #expect(viewModel.approvalButtons[0].state.title == "swap.approving_button".localized)

        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await responses.count == 4 })
        await responses.complete(4, state0: .allowed, state1: .allowed)
        try #require(await waitUntil { viewModel.approvalButtons.isEmpty })
    }

    @Test func queryStartedBeforeSubmissionCannotClearImmediateProgress() async throws {
        let token0 = token(index: 1)
        let token1 = token(index: 2)
        let responses = ApprovalQuoteRequests(token0: token0, token1: token1)
        let provider = RefreshTestProvider(quote: { await responses.quote() })
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await responses.completeAll() }
        }
        try #require(await waitUntil { viewModel.approvalButtons.count == 2 })
        let step = try #require(viewModel.approvalButtons[0].state.preSwapStep)
        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await responses.count == 2 })

        viewModel.onAllowanceSubmitted(token: token0, providerId: provider.id, step: step)
        try #require(await waitUntil { await responses.count == 3 })
        await responses.complete(2, state0: insufficientAllowance(token: token0), state1: insufficientAllowance(token: token1))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(viewModel.approvalButtons[0].state.showProgress)

        // A fresh insufficient result hands control back to the normal state.
        await responses.complete(3, state0: insufficientAllowance(token: token0), state1: insufficientAllowance(token: token1))
        try #require(await waitUntil { viewModel.approvalButtons.first?.state.showProgress == false })
        #expect(viewModel.approvalButtons[0].state.preSwapStep != nil)
    }

    @Test func manualSubmissionShowsProgressAndResetClearsIt() async throws {
        let requests = AllowanceRequests()
        let provider = RefreshTestProvider(
            quote: { throw TestError.noPool },
            allowance: { token, amount in await requests.request(token: token, amount: amount) }
        )
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await requests.completeAll() }
        }
        try #require(await waitUntil { viewModel.isSafeSwapManualAmountOutMode })
        viewModel.manualAmountOutString = "1"
        try #require(await waitUntil { await requests.count == 2 })
        await requests.completeAll(state: insufficientAllowance(token: token(index: 1)))
        try #require(await waitUntil { viewModel.approvalButtons.first?.state.preSwapStep != nil })
        let button = try #require(viewModel.approvalButtons.first)
        let step = try #require(button.state.preSwapStep)

        viewModel.onAllowanceSubmitted(token: button.token, providerId: provider.id, step: step)
        #expect(viewModel.approvalButtons[0].state.showProgress)
        #expect(!viewModel.approvalButtons[1].state.showProgress)
        try #require(await waitUntil { await requests.count == 4 })
        await requests.completeAll()
        try #require(await waitUntil { viewModel.approvalButtons.isEmpty })

        viewModel.onAllowanceSubmitted(token: button.token, providerId: provider.id, step: step)
        viewModel.reset()
        #expect(viewModel.approvalButtonState(token: button.token, providerId: provider.id, fallback: nil) == nil)
    }

    @Test func dismissingWithoutSubmissionDoesNotShowApproving() async throws {
        let responses = ApprovalQuoteRequests(token0: token(index: 1), token1: token(index: 2))
        let provider = RefreshTestProvider(quote: { await responses.quote() })
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            Task { await responses.completeAll() }
        }
        try #require(await waitUntil { viewModel.approvalButtons.count == 2 })
        viewModel.refreshAfterPreSwap()
        #expect(viewModel.approvalButtons.allSatisfy { !$0.state.showProgress && !$0.state.disabled })
    }

    private func insufficientAllowance(token: Token) -> LiquidityAddAllowanceHelper.AllowanceState {
        .notEnough(appValue: AppValue(token: token, value: 0), spenderAddress: Address(raw: "spender"), revokeRequired: false)
    }

    @Test func silentFailureAfterClosingApprovalRetriesWithoutAnotherUserAction() async throws {
        let responses = QuoteResponses()
        let provider = RefreshTestProvider(quote: { try await responses.quote() })
        let viewModel = makeViewModel(provider: provider, refreshDuration: 0.1)
        defer { viewModel.stopAutoQuoting() }
        try #require(await waitUntil { viewModel.currentQuote != nil })

        // Opening an approval sheet stops normal quoting; cancelling it never
        // starts pending-approval polling. Its dismiss callback refreshes silently.
        viewModel.stopAutoQuoting()
        await responses.failNextQuote()
        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await responses.failureCount == 1 })
        try #require(await waitUntil { await responses.successCount >= 2 })
        #expect(viewModel.currentQuote != nil)
        #expect(viewModel.nextQuoteTime != nil)
    }

    @Test func repeatedRefreshesAllowSlowManualAllowanceRequestsToFinish() async throws {
        let requests = AllowanceRequests()
        let provider = RefreshTestProvider(
            quote: { throw TestError.noPool },
            allowance: { token, amount in await requests.request(token: token, amount: amount) }
        )
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            viewModel.stopPendingAllowanceRefresh()
            Task { await requests.completeAll() }
        }
        try #require(await waitUntil { viewModel.isSafeSwapManualAmountOutMode })
        viewModel.manualAmountOutString = "1"
        try #require(await waitUntil { await requests.count == 2 })

        // Hold RPC replies while multiple refresh ticks arrive.
        for _ in 0 ..< 5 {
            viewModel.refreshAfterPreSwap()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(await requests.count == 2)
        await requests.completeAll()
        try #require(await waitUntil { viewModel.approvalButtons.isEmpty })

        // A background refresh must preserve the confirmed state while waiting.
        viewModel.refreshAfterPreSwap()
        try #require(await waitUntil { await requests.count >= 4 })
        #expect(viewModel.approvalButtons.isEmpty)
    }

    @Test func changingManualAmountDiscardsOldAllowanceResults() async throws {
        let requests = AllowanceRequests()
        let provider = RefreshTestProvider(
            quote: { throw TestError.noPool },
            allowance: { token, amount in await requests.request(token: token, amount: amount) }
        )
        let viewModel = makeViewModel(provider: provider)
        defer {
            viewModel.stopAutoQuoting()
            Task { await requests.completeAll() }
        }
        try #require(await waitUntil { viewModel.isSafeSwapManualAmountOutMode })
        viewModel.manualAmountOutString = "1"
        try #require(await waitUntil { await requests.count == 2 })
        viewModel.manualAmountOutString = "2"
        try #require(await waitUntil { await requests.count == 4 })

        await requests.completeFirst(2)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(!viewModel.approvalButtons.isEmpty)
        #expect(await requests.amounts.contains(2))
        await requests.completeAll()
        try #require(await waitUntil { viewModel.approvalButtons.isEmpty })
    }

    private func makeViewModel(provider: RefreshTestProvider, refreshDuration: Double = 20) -> LiquidityAddViewModel {
        let viewModel = LiquidityAddViewModel(providers: [provider], autoRefreshDuration: refreshDuration)
        viewModel.tokenIn = token(index: 1)
        viewModel.tokenOut = token(index: 2)
        viewModel.amountIn = 1
        viewModel.adapterState = .synced
        viewModel.adapterStateOut = .synced
        viewModel.availableBalance = 10
        viewModel.availableBalanceOut = 10
        return viewModel
    }

    private func token(index: Int) -> Token {
        Token(
            coin: Coin(uid: "refresh-test-\(index)", name: "Test", code: "TEST"),
            blockchain: Blockchain(type: .safe4, name: "SAFE", explorerUrl: nil),
            type: .eip20(address: "0x000000000000000000000000000000000000000\(index)"),
            decimals: 18
        )
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws -> Bool {
        for _ in 0 ..< 200 {
            if await condition() { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

private enum TestError: Error { case noPool }

private struct FailingAllowanceAdapter: IAllowanceAdapter {
    var pendingTransactions: [TransactionRecord] { [] }

    func allowance(spenderAddress _: Address, defaultBlockParameter _: BlockParameter) async throws -> Decimal {
        throw URLError(.timedOut)
    }
}

private actor QuoteResponses {
    private var shouldFail = false
    private(set) var successCount = 0
    private(set) var failureCount = 0

    func failNextQuote() { shouldFail = true }

    func quote() throws -> LiquidityAddQuote {
        if shouldFail {
            shouldFail = false
            failureCount += 1
            throw TestError.noPool
        }
        successCount += 1
        return LiquidityAddQuote(expectedBuyAmount: 1)
    }
}

private actor AllowanceRequests {
    private var continuations: [CheckedContinuation<LiquidityAddAllowanceHelper.AllowanceState, Never>] = []
    private(set) var amounts: [Decimal] = []
    var count: Int { amounts.count }

    func request(token _: Token, amount: Decimal) async -> LiquidityAddAllowanceHelper.AllowanceState {
        amounts.append(amount)
        return await withCheckedContinuation { continuations.append($0) }
    }

    func completeFirst(_ count: Int, state: LiquidityAddAllowanceHelper.AllowanceState = .allowed) {
        let completed = Array(continuations.prefix(count))
        continuations.removeFirst(completed.count)
        completed.forEach { $0.resume(returning: state) }
    }

    func completeAll(state: LiquidityAddAllowanceHelper.AllowanceState = .allowed) { completeFirst(continuations.count, state: state) }
}

private actor ApprovalQuoteRequests {
    private let token0: Token
    private let token1: Token
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<LiquidityAddQuote, Never>] = [:]

    init(token0: Token, token1: Token) {
        self.token0 = token0
        self.token1 = token1
    }

    func quote() async -> LiquidityAddQuote {
        count += 1
        if count == 1 {
            return quote(
                state0: .notEnough(appValue: AppValue(token: token0, value: 0), spenderAddress: Address(raw: "spender"), revokeRequired: false),
                state1: .notEnough(appValue: AppValue(token: token1, value: 0), spenderAddress: Address(raw: "spender"), revokeRequired: false)
            )
        }
        let id = count
        return await withCheckedContinuation { continuations[id] = $0 }
    }

    func complete(_ id: Int, state0: LiquidityAddAllowanceHelper.AllowanceState, state1: LiquidityAddAllowanceHelper.AllowanceState) {
        continuations.removeValue(forKey: id)?.resume(returning: quote(state0: state0, state1: state1))
    }

    func completeAll() {
        let pending = continuations
        continuations = [:]
        for continuation in pending.values {
            continuation.resume(returning: quote(state0: .allowed, state1: .allowed))
        }
    }

    private func quote(state0: LiquidityAddAllowanceHelper.AllowanceState, state1: LiquidityAddAllowanceHelper.AllowanceState) -> LiquidityAddQuote {
        EvmLiquidityAddQuote(expectedBuyAmount: 1, requiredAmount1: 1, allowanceState0: state0, allowanceState1: state1)
    }
}

private class RefreshTestProvider: BaseEvmLiquidityAddProvider {
    private let quoteResponse: () async throws -> LiquidityAddQuote
    private let allowanceResponse: (Token, Decimal) async -> LiquidityAddAllowanceHelper.AllowanceState

    init(quote: @escaping () async throws -> LiquidityAddQuote, allowance: @escaping (Token, Decimal) async -> LiquidityAddAllowanceHelper.AllowanceState = { _, _ in .allowed }) {
        quoteResponse = quote
        allowanceResponse = allowance
        super.init(storage: MultiSwapSettingStorage())
    }

    override var id: String { "safeswap" }
    override func supports(token0 _: Token, token1 _: Token) -> Bool { true }
    override func quote(token0 _: Token, token1 _: Token, amount0 _: Decimal) async throws -> LiquidityAddQuote {
        try await quoteResponse()
    }
    override func allowanceState(token: Token, amount: Decimal) async -> LiquidityAddAllowanceHelper.AllowanceState {
        await allowanceResponse(token, amount)
    }
}
