import Combine
import BigInt
import Foundation
import HsExtensions
import MarketKit
import RxSwift

class LiquidityAddViewModel: ObservableObject {
    let autoRefreshDuration: Double = 20
    private let quoteTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static let defaultV3RangePercent = 20

    private var cancellables = Set<AnyCancellable>()
    private var providerCancellables = Set<AnyCancellable>()
    private var quotesTask: AnyTask?
    private var swapTask: AnyTask?
    private var rateInCancellable: AnyCancellable?
    private var rateOutCancellable: AnyCancellable?
    private var timer: Timer?

    private var balanceDisposeBag = DisposeBag()
    private var balanceOutDisposeBag = DisposeBag()

    private var providers: [ILiquidityAddProvider]
    private let evmBlockchainManager = Core.shared.evmBlockchainManager
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let walletManager = Core.shared.walletManager
    private let adapterManager = Core.shared.adapterManager
    private let localStorage = Core.shared.localStorage
    private let decimalParser = AmountDecimalParser()

    @Published var currency: Currency

    private var enteringFiat = false

    @Published var validProviders = [ILiquidityAddProvider]()

    private var internalTokenIn: Token? {
        didSet {
            guard internalTokenIn != oldValue else {
                return
            }

            syncValidProviders()

            if internalTokenIn != tokenIn {
                tokenIn = internalTokenIn
            }

            if let internalTokenIn {
                coinPriceIn = marketKit.coinPrice(coinUid: internalTokenIn.coin.uid, currencyCode: currency.code)
                rateInCancellable = marketKit.coinPricePublisher(coinUid: internalTokenIn.coin.uid, currencyCode: currency.code)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] price in self?.coinPriceIn = price }
            } else {
                coinPriceIn = nil
                rateInCancellable = nil
            }

            balanceDisposeBag = .init()

            if let internalTokenIn,
               let wallet = walletManager.activeWallets.first(where: { $0.token == internalTokenIn }),
               let adapter = adapterManager.balanceAdapter(for: wallet)
            {
                adapterState = adapter.balanceState
                availableBalance = adapter.balanceData.available

                adapter.balanceStateUpdatedObservable
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] state in
                        self?.adapterState = state
                    }
                    .disposed(by: balanceDisposeBag)

                adapter.balanceDataUpdatedObservable
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] balanceData in
                        self?.availableBalance = balanceData.available
                    }
                    .disposed(by: balanceDisposeBag)
            } else {
                adapterState = nil
                availableBalance = nil
            }
        }
    }

    @Published var tokenIn: Token? {
        didSet {
            guard internalTokenIn != tokenIn else {
                return
            }

            if enteringFiat {
                fiatAmountIn = nil
            } else {
                amountIn = nil
            }

            internalTokenIn = tokenIn

            if internalTokenOut == tokenIn {
                internalTokenOut = nil
            }

            priceFlipped = false
            internalUserSelectedProviderId = nil
            resetV3TickType()

            syncQuotes()
        }
    }

    private var internalTokenOut: Token? {
        didSet {
            guard internalTokenOut != oldValue else {
                return
            }

            syncValidProviders()

            if internalTokenOut != tokenOut {
                tokenOut = internalTokenOut
            }

            if let internalTokenOut {
                rateOut = marketKit.coinPrice(coinUid: internalTokenOut.coin.uid, currencyCode: currency.code)?.value
                rateOutCancellable = marketKit.coinPricePublisher(coinUid: internalTokenOut.coin.uid, currencyCode: currency.code)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] price in self?.rateOut = price.value }
            } else {
                rateOut = nil
                rateOutCancellable = nil
            }

            balanceOutDisposeBag = .init()

            if let internalTokenOut,
               let wallet = walletManager.activeWallets.first(where: { $0.token == internalTokenOut }),
               let adapter = adapterManager.balanceAdapter(for: wallet)
            {
                adapterStateOut = adapter.balanceState
                availableBalanceOut = adapter.balanceData.available

                adapter.balanceStateUpdatedObservable
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] state in
                        self?.adapterStateOut = state
                    }
                    .disposed(by: balanceOutDisposeBag)

                adapter.balanceDataUpdatedObservable
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .observeOn(MainScheduler.instance)
                    .subscribe { [weak self] balanceData in
                        self?.availableBalanceOut = balanceData.available
                    }
                    .disposed(by: balanceOutDisposeBag)
            } else {
                adapterStateOut = nil
                availableBalanceOut = nil
            }
        }
    }

    @Published var tokenOut: Token? {
        didSet {
            guard internalTokenOut != tokenOut else {
                return
            }

            internalTokenOut = tokenOut

            if internalTokenIn == tokenOut {
                amountIn = nil
                internalTokenIn = nil
            }

            priceFlipped = false
            internalUserSelectedProviderId = nil
            resetV3TickType()

            syncQuotes()
        }
    }

    @Published var adapterState: AdapterState?
    @Published var availableBalance: Decimal?
    @Published var adapterStateOut: AdapterState?
    @Published var availableBalanceOut: Decimal?

    @Published var coinPriceIn: CoinPrice? {
        didSet {
            syncFiatAmountIn()
        }
    }

    @Published var rateOut: Decimal? {
        didSet {
            syncFiatAmountOut()
        }
    }

    var amountIn: Decimal? {
        didSet {
            internalUserSelectedProviderId = nil

            syncQuotes()
            syncFiatAmountIn()

            let amount = decimalParser.parseAnyDecimal(from: amountString)

            if amount != amountIn {
                amountString = amountIn?.description ?? ""
            }
        }
    }

    @Published var amountString: String = "" {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: amountString)

            guard amount != amountIn else {
                return
            }

            enteringFiat = false

            amountIn = amount
        }
    }

    @Published var fiatAmountIn: Decimal? {
        didSet {
            syncAmountIn()

            let amount = decimalParser.parseAnyDecimal(from: fiatAmountString)?.rounded(decimal: 2)

            if amount != fiatAmountIn {
                fiatAmountString = fiatAmountIn?.description ?? ""
            }
        }
    }

    @Published var fiatAmountString: String = "" {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: fiatAmountString)?.rounded(decimal: 2)

            guard amount != fiatAmountIn else {
                return
            }

            enteringFiat = true

            fiatAmountIn = amount
        }
    }

    @Published var v3LowestPrice: String?
    @Published var v3HighestPrice: String?
    @Published var v3CurrentPrice: String?
    @Published var v3PriceError: String?

    private var v3TickLower: BigInt?
    private var v3TickUpper: BigInt?
    private var v3TickSpacing: BigUInt?

    private var v3TickType: LiquidityTickType = .full
    private var shouldApplyInitialV3Range = true
    
    var currentV3TickType: LiquidityTickType? {
        guard v3Enabled else { return nil }
        // 直接使用 provider 的 tickType，确保与报价时一致
        if let provider = currentQuote?.provider as? BaseUniswapV3LiquidityAddProvider {
            return provider.tickType
        }
        return v3TickType
    }

    @Published var currentQuote: Quote? {
        didSet {
            amountOutString = currentQuote?.quote.expectedBuyAmount.description
            syncFiatAmountOut()
            syncPrice()
            syncV3Prices()
        }
    }

    @Published var bestQuote: Quote?

    private var internalUserSelectedProviderId: String? {
        didSet {
            guard internalUserSelectedProviderId != oldValue else {
                return
            }

            if internalUserSelectedProviderId != userSelectedProviderId {
                userSelectedProviderId = internalUserSelectedProviderId
            }
        }
    }

    @Published var userSelectedProviderId: String? {
        didSet {
            guard userSelectedProviderId != internalUserSelectedProviderId else {
                return
            }

            internalUserSelectedProviderId = userSelectedProviderId
            syncCurrentQuote()
        }
    }

    @Published var quotes: [Quote] = [] {
        didSet {
            if let featuredQuote = quotes.first(where: { $0.provider is OneInchMultiSwapProvider }) {
                bestQuote = featuredQuote
            } else {
                bestQuote = quotes.max { $0.quote.expectedBuyAmount < $1.quote.expectedBuyAmount }
            }

            syncCurrentQuote()

            timer?.invalidate()
            nextQuoteTime = nil

            if !quotes.isEmpty {
                nextQuoteTime = Date().timeIntervalSince1970 + autoRefreshDuration

                // 自动刷新时使用silent: true避免UI闪烁
                timer = Timer.scheduledTimer(withTimeInterval: autoRefreshDuration, repeats: false) { [weak self] _ in
                    self?.syncQuotes(silent: true)
                }
            }
        }
    }

    @Published var amountOutString: String?
    @Published var fiatAmountOut: Decimal? {
        didSet {
            syncPriceImpact()
        }
    }

    @Published var price: String?
    private var priceFlipped = false

    @Published var quoting = false
    @Published var nextQuoteTime: Double?

    @Published var priceImpact: Decimal?

    init(providers: [ILiquidityAddProvider], token: Token? = nil) {
        self.providers = providers
        currency = currencyManager.baseCurrency

        defer {
            internalTokenIn = token
            internalTokenOut = MultiSwapDefaultTokenResolver.default(for: token)
        }

        currencyManager.$baseCurrency.sink { [weak self] in self?.currency = $0 }.store(in: &cancellables)
    }

    func subscribeToProviders() {
        providerCancellables = Set<AnyCancellable>()

        for provider in providers {
            if let syncPublisher = provider.syncPublisher {
                syncPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in
                        self?.syncValidProviders()
                        self?.syncQuotes(silent: true)
                    }
                    .store(in: &providerCancellables)
            }
        }
    }

    private func syncValidProviders() {
        if let internalTokenIn, let internalTokenOut {
            validProviders = providers.filter { $0.supports(token0: internalTokenIn, token1: internalTokenOut) }
        } else {
            validProviders = []
        }
    }

    private func syncCurrentQuote() {
        if let internalUserSelectedProviderId {
            currentQuote = quotes.first { $0.provider.id == internalUserSelectedProviderId } ?? bestQuote
        } else {
            currentQuote = bestQuote
        }
    }

    private func syncAmountIn() {
        guard enteringFiat else {
            return
        }

        guard let coinPriceIn, let fiatAmountIn else {
            amountIn = nil
            return
        }

        amountIn = fiatAmountIn / coinPriceIn.value
    }

    private func syncFiatAmountIn() {
        guard !enteringFiat else {
            return
        }

        guard let coinPriceIn, let amountIn else {
            fiatAmountIn = nil
            return
        }

        fiatAmountIn = (amountIn * coinPriceIn.value).rounded(decimal: 2)
    }

    private func syncFiatAmountOut() {
        guard let rateOut else {
            fiatAmountOut = nil
            return
        }

        let amountOut = currentQuote?.quote.expectedBuyAmount
        guard let amountOut else {
            fiatAmountOut = nil
            return
        }

        fiatAmountOut = (amountOut * rateOut).rounded(decimal: 2)
    }

    func syncPriceImpact() {
        guard let fiatAmountIn, let fiatAmountOut, fiatAmountIn != 0 else {
            priceImpact = nil
            return
        }

        priceImpact = (fiatAmountOut * 100 / fiatAmountIn) - 100
    }

    func syncQuotes(silent: Bool = false) {
        quotesTask?.cancel()
        quotesTask = nil

        if !silent {
            quotes = []
        }

        guard let internalTokenIn, let internalTokenOut, let amountIn, amountIn != 0 else {
            if quoting {
                quoting = false
            }

            return
        }

        guard !validProviders.isEmpty else {
            if quoting {
                quoting = false
            }

            return
        }

        if !quoting, !silent {
            quoting = true
        }

        quotesTask = Task { [weak self, validProviders] in
            let optionalQuotes: [Quote?] = await withTaskGroup(of: Quote?.self) { group in
                for provider in validProviders {
                    group.addTask {
                        do {
                            if let provider = provider as? BaseUniswapV3LiquidityAddProvider {
                                provider.tickType = self?.v3TickType ?? .full
                            }

                            let quoteTask = Task {
                                try await provider.quote(token0: internalTokenIn, token1: internalTokenOut, amount0: amountIn)
                            }

                            let timeoutTask = Task {
                                try await Task.sleep(nanoseconds: self?.quoteTimeoutNanoseconds ?? 15_000_000_000)
                                quoteTask.cancel()
                            }

                            return try await withTaskCancellationHandler {
                                let quote = try await quoteTask.value
                                timeoutTask.cancel()

                                return Quote(provider: provider, quote: quote)
                            } onCancel: {
                                quoteTask.cancel()
                                timeoutTask.cancel()
                            }
                        } catch {
                            print("QUOTE ERROR: \(provider.id): \(error)")
                            return nil
                        }
                    }
                }

                var quotes = [Quote?]()

                for await quote in group {
                    quotes.append(quote)
                }

                return quotes
            }

            let quotes = optionalQuotes.compactMap { $0 }.sorted { $0.quote.expectedBuyAmount > $1.quote.expectedBuyAmount }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }

                    self.quoting = false

                    // 无论是否为空，都更新quotes以反映最新的授权状态
                    self.quotes = quotes
                    
                    // 如果quotes为空且不是静默刷新，设置定时器重试
                    if quotes.isEmpty && !silent {
                        self.timer?.invalidate()
                        self.nextQuoteTime = Date().timeIntervalSince1970 + self.autoRefreshDuration
                        self.timer = Timer.scheduledTimer(withTimeInterval: self.autoRefreshDuration, repeats: false) { [weak self] _ in
                            self?.syncQuotes(silent: true)
                        }
                    }
                }
            }
        }
        .erased()
    }

    private func syncPrice() {
        if let tokenIn, let tokenOut, let amountIn, amountIn != 0, let amountOut = currentQuote?.quote.expectedBuyAmount {
            var showAsIn = amountIn < amountOut

            if priceFlipped {
                showAsIn.toggle()
            }

            let tokenA = showAsIn ? tokenIn : tokenOut
            let tokenB = showAsIn ? tokenOut : tokenIn
            let amountA = showAsIn ? amountIn : amountOut
            let amountB = showAsIn ? amountOut : amountIn

            let formattedValue = ValueFormatter.instance.formatFull(value: amountB / amountA, decimalCount: tokenB.decimals)
            price = formattedValue.map { "1 \(tokenA.coin.code) = \($0) \(tokenB.coin.code)" }
        } else {
            price = nil
        }
    }

    private func syncV3Prices() {
        guard let tokenIn, let tokenOut,
              let provider = currentQuote?.provider as? BaseUniswapV3LiquidityAddProvider,
              let quote = currentQuote?.quote as? UniswapLiquidityAddQuote,
              case let .v3(bestTrade) = quote.trade,
              let tickInfo = bestTrade.tickInfo
        else {
            v3LowestPrice = nil
            v3HighestPrice = nil
            v3CurrentPrice = nil
            v3TickLower = nil
            v3TickUpper = nil
            v3TickSpacing = nil
            v3PriceError = nil
            return
        }

        v3TickLower = tickInfo.tickLower
        v3TickUpper = tickInfo.tickUpper
        v3TickSpacing = tickInfo.tickSpacing

        do {
            let sortsBefore = try provider.tokensSortBefore(token0: tokenIn, token1: tokenOut)
            
            if sortsBefore {
                v3LowestPrice = tickInfo.isMinTick ? "0" : tickInfo.tickLowerPrice?.description
                v3HighestPrice = tickInfo.isMaxTick ? "∞" : tickInfo.tickUpperPrice?.description
            } else {
                v3LowestPrice = tickInfo.isMaxTick ? "0" : tickInfo.tickUpperPrice?.description
                v3HighestPrice = tickInfo.isMinTick ? "∞" : tickInfo.tickLowerPrice?.description
            }
            v3CurrentPrice = tickInfo.tickcurrentPrice?.description
        } catch {
            v3LowestPrice = tickInfo.isMinTick ? "0" : tickInfo.tickLowerPrice?.description
            v3HighestPrice = tickInfo.isMaxTick ? "∞" : tickInfo.tickUpperPrice?.description
            v3CurrentPrice = tickInfo.tickcurrentPrice?.description
        }

        let lower = tickInfo.tickLower
        let upper = tickInfo.tickUpper

        if lower == provider.minTickValue, upper == provider.maxTickValue {
            v3TickType = .full
        } else {
            v3TickType = .range(lower: lower, upper: upper)
        }

        if shouldApplyInitialV3Range,
           case .full = v3TickType,
           applyV3Range(percent: Self.defaultV3RangePercent)
        {
            shouldApplyInitialV3Range = false
            syncQuotes()
        }
    }
}

extension LiquidityAddViewModel {
    private var selectedProvider: ILiquidityAddProvider? {
        if let userSelectedProviderId {
            return validProviders.first(where: { $0.id == userSelectedProviderId })
        }

        return currentQuote?.provider
    }

    var v3Enabled: Bool {
        selectedProvider is BaseUniswapV3LiquidityAddProvider
    }

    func onChangeV3LowestPrice(text: String) {
        setV3Price(type: .lowest, text: text)
    }

    func onChangeV3HighestPrice(text: String) {
        setV3Price(type: .highest, text: text)
    }

    func onTapV3LowestMinus() {
        changeV3Tick(type: .lowest, delta: -1)
    }

    func onTapV3LowestPlus() {
        changeV3Tick(type: .lowest, delta: 1)
    }

    func onTapV3HighestMinus() {
        changeV3Tick(type: .highest, delta: -1)
    }

    func onTapV3HighestPlus() {
        changeV3Tick(type: .highest, delta: 1)
    }

    func setV3TickRange(percent: Int?) {
        shouldApplyInitialV3Range = false
        v3PriceError = nil

        if let percent {
            guard applyV3Range(percent: percent) else {
                return
            }
        } else {
            v3TickType = .full
        }

        syncQuotes()
    }

    private func applyV3Range(percent: Int) -> Bool {
        guard let provider = currentQuote?.provider as? BaseUniswapV3LiquidityAddProvider,
              let quote = currentQuote?.quote as? UniswapLiquidityAddQuote,
              case let .v3(bestTrade) = quote.trade,
              let tickInfo = bestTrade.tickInfo
        else {
            return false
        }

        let currentTick = tickInfo.tickCurrent
        let distance = max(
            BigInt(tickInfo.tickSpacing),
            BigInt(currentTick.magnitude) * BigInt(percent) / 100
        )

        let lower = max(provider.minTickValue, currentTick - distance)
        let upper = min(provider.maxTickValue, currentTick + distance)

        guard upper > lower else {
            return false
        }

        v3TickLower = lower
        v3TickUpper = upper
        v3TickType = .range(lower: lower, upper: upper)
        return true
    }

    private enum V3PriceType {
        case lowest
        case highest
    }

    private func setV3Price(type: V3PriceType, text: String) {
        guard let tokenIn, let tokenOut,
              let provider = currentQuote?.provider as? BaseUniswapV3LiquidityAddProvider
        else {
            return
        }

        let parsed = decimalParser.parseAnyDecimal(from: text)
        guard let price = parsed else {
            v3PriceError = "无效的价格输入"
            return
        }

        do {
            let sortsBefore = try provider.tokensSortBefore(token0: tokenIn, token1: tokenOut)
            let tick: BigInt

            if price == 0 {
                tick = sortsBefore ? provider.minTickValue : provider.maxTickValue
            } else {
                tick = try provider.tickFromPrice(price: price, token0: tokenIn, token1: tokenOut)
            }

            let adjustedTick: BigInt
            switch (type, sortsBefore) {
            case (.lowest, true):
                adjustedTick = max(tick, provider.minTickValue)
                if let upper = v3TickUpper, adjustedTick >= upper {
                    v3PriceError = "最低价格必须小于最高价格"
                    return
                }
                v3TickLower = adjustedTick
            case (.lowest, false):
                adjustedTick = min(tick, provider.maxTickValue)
                if let lower = v3TickLower, adjustedTick <= lower {
                    v3PriceError = "最低价格必须小于最高价格"
                    return
                }
                v3TickUpper = adjustedTick
            case (.highest, true):
                adjustedTick = min(tick, provider.maxTickValue)
                if let lower = v3TickLower, adjustedTick <= lower {
                    v3PriceError = "最高价格必须大于最低价格"
                    return
                }
                v3TickUpper = adjustedTick
            case (.highest, false):
                adjustedTick = max(tick, provider.minTickValue)
                if let upper = v3TickUpper, adjustedTick >= upper {
                    v3PriceError = "最高价格必须大于最低价格"
                    return
                }
                v3TickLower = adjustedTick
            }

            v3PriceError = nil
            shouldApplyInitialV3Range = false
            applyV3TickType(provider: provider)
        } catch {
            v3PriceError = "价格转换失败"
            return
        }
    }

    private func changeV3Tick(type: V3PriceType, delta: Int) {
        guard let tokenIn, let tokenOut,
              let provider = currentQuote?.provider as? BaseUniswapV3LiquidityAddProvider,
              let tickSpacing = v3TickSpacing,
              let lower = v3TickLower,
              let upper = v3TickUpper
        else {
            return
        }

        do {
            let sortsBefore = try provider.tokensSortBefore(token0: tokenIn, token1: tokenOut)
            let step = BigInt(tickSpacing) * BigInt(delta)

            if sortsBefore {
                switch type {
                case .lowest:
                    let candidate = lower + step
                    guard candidate < upper else {
                        v3PriceError = "最低价格不能超过最高价格"
                        return
                    }
                    v3TickLower = max(provider.minTickValue, candidate)
                case .highest:
                    let candidate = upper + step
                    guard candidate > lower else {
                        v3PriceError = "最高价格不能低于最低价格"
                        return
                    }
                    v3TickUpper = min(provider.maxTickValue, candidate)
                }
            } else {
                switch type {
                case .lowest:
                    let candidate = upper - step
                    guard candidate > lower else {
                        v3PriceError = "最低价格不能超过最高价格"
                        return
                    }
                    v3TickUpper = min(provider.maxTickValue, candidate)
                case .highest:
                    let candidate = lower - step
                    guard candidate < upper else {
                        v3PriceError = "最高价格不能低于最低价格"
                        return
                    }
                    v3TickLower = max(provider.minTickValue, candidate)
                }
            }

            v3PriceError = nil
            applyV3TickType(provider: provider)
        } catch {
            return
        }
    }

    private func applyV3TickType(provider: BaseUniswapV3LiquidityAddProvider) {
        if let lower = v3TickLower, let upper = v3TickUpper, upper <= lower {
            return
        }

        if let lower = v3TickLower, let upper = v3TickUpper, lower == provider.minTickValue, upper == provider.maxTickValue {
            v3TickType = .full
        } else {
            v3TickType = .range(lower: v3TickLower, upper: v3TickUpper)
        }

        syncQuotes()
    }

    private func resetV3TickType() {
        v3TickType = .full
        shouldApplyInitialV3Range = true
    }
}

extension LiquidityAddViewModel {
    struct ApprovalButton {
        let title: String
        let state: MultiSwapButtonState
        let token: Token
        let otherToken: Token
        let amount: Decimal
        let provider: ILiquidityAddProvider
    }

    var approvalButtons: [ApprovalButton] {
        guard let tokenIn, let tokenOut, let amountIn, amountIn > 0 else {
            return []
        }

        guard let adapterState, let adapterStateOut, adapterState.isSynced, adapterStateOut.isSynced, !adapterState.syncing, !adapterStateOut.syncing else {
            return []
        }

        guard let availableBalance, amountIn <= availableBalance else {
            return []
        }

        if let currentQuote, let quote = currentQuote.quote as? UniswapLiquidityAddQuote {
            let amountOut = quote.expectedBuyAmount

            guard let availableBalanceOut, amountOut <= availableBalanceOut else {
                return []
            }

            var buttons = [ApprovalButton]()
            if let state0 = quote.allowanceState0.customButtonState {
                buttons.append(
                    ApprovalButton(
                        title: "\(state0.title) 1",
                        state: state0,
                        token: tokenIn,
                        otherToken: tokenOut,
                        amount: amountIn,
                        provider: currentQuote.provider
                    )
                )
            }

            if let state1 = quote.allowanceState1.customButtonState {
                buttons.append(
                    ApprovalButton(
                        title: "\(state1.title) 2",
                        state: state1,
                        token: tokenOut,
                        otherToken: tokenIn,
                        amount: amountOut,
                        provider: currentQuote.provider
                    )
                )
            }

            return buttons
        }
        return []
    }

    func refreshAfterPreSwap() {
        syncQuotes()
    }
}

extension LiquidityAddViewModel {
    func interchange() {
        let currentFiatAmountOut = fiatAmountOut
        let currentAmountOut = currentQuote?.quote.expectedBuyAmount

        let internalTokenIn = internalTokenIn
        self.internalTokenIn = internalTokenOut
        internalTokenOut = internalTokenIn

        if enteringFiat {
            fiatAmountIn = currentFiatAmountOut
        } else {
            amountIn = currentAmountOut
        }
    }

    func flipPrice() {
        priceFlipped.toggle()
        syncPrice()
    }

    func setAmountIn(percent: Int) {
        guard let tokenIn, let availableBalance else {
            return
        }

        enteringFiat = false

        amountIn = (availableBalance * Decimal(percent) / 100).rounded(decimal: tokenIn.decimals)
    }

    func clearAmountIn() {
        enteringFiat = false
        amountIn = nil
    }

    func stopAutoQuoting() {
        timer?.invalidate()
        quotesTask?.cancel()
        quotesTask = nil
    }

    func autoQuoteIfRequired() {
        guard !quoting, let nextQuoteTime else {
            return
        }

        let now = Date().timeIntervalSince1970

        if now > nextQuoteTime {
            syncQuotes(silent: true)
        } else {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: nextQuoteTime - now, repeats: false) { [weak self] _ in
                self?.syncQuotes(silent: true)
            }
        }
    }

    func reset() {
        amountIn = nil
        internalTokenIn = nil
        internalTokenOut = nil
    }
}

extension LiquidityAddViewModel {
    var shouldShowTerms: Bool {
        guard let currentQuote else {
            return false
        }

        return currentQuote.provider.requireTerms && !localStorage.liquidityTermsAccepted
    }

    func onAcceptTerms() {
        localStorage.liquidityTermsAccepted = true
    }
}

extension LiquidityAddViewModel {
    struct Quote {
        let provider: ILiquidityAddProvider
        let quote: LiquidityAddQuote
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
