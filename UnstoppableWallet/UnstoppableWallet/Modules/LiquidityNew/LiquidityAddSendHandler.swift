import BigInt
import Combine
import Eip20Kit
import EvmKit
import Foundation
import MarketKit

class LiquidityAddSendHandler {
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let accountManager = Core.shared.accountManager
    private let walletManager = Core.shared.walletManager
    private let evmBlockchainManager = Core.shared.evmBlockchainManager
    private let adapterManager = Core.shared.adapterManager
    private let tronKitManager = Core.shared.tronAccountManager.tronKitManager
    private let mevProtectionHelper = MevProtectionHelper()
    
    let baseToken: Token
    let token0: Token
    let token1: Token
    let amount0: Decimal
    let amount1: Decimal
    let provider: ILiquidityAddProvider
    let v3TickType: LiquidityTickType?
    let manualAmountOutMode: Bool

    private var slippage = MultiSwapSlippage.default
    private var recipient: String?

    private let refreshSubject = PassthroughSubject<Void, Never>()
    
    init(baseToken: Token, token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider, v3TickType: LiquidityTickType? = nil, manualAmountOutMode: Bool = false) {
        self.baseToken = baseToken
        self.token0 = token0
        self.token1 = token1
        self.amount0 = amount0
        self.amount1 = amount1
        self.provider = provider
        self.v3TickType = v3TickType
        self.manualAmountOutMode = manualAmountOutMode
    }
}

extension LiquidityAddSendHandler: ISendHandler {
    var syncingText: String? {
        "swap.confirmation.quoting".localized
    }

    var expirationDuration: Int? {
        15
    }

    var menuItems: [SendMenuItem] {
        var menuItems = [SendMenuItem]()

        if provider.slippageSupported(token0: token0, token1: token1) {
            menuItems.append(
                .init(label: "swap.confirmation.slippage_tolerance".localized) { [weak self] in
                    guard let self else {
                        return
                    }

                    Coordinator.shared.present { _ in
                        MultiSwapSlippageView(slippage: self.slippage) { [weak self] slippage in
                            self?.slippage = slippage
                            self?.refreshSubject.send()
                        }
                    }
                }
            )
        }

        menuItems.append(
            .init(label: "swap.confirmation.set_recipient".localized) { [weak self] in
                guard let self else {
                    return
                }

                Coordinator.shared.present { _ in
                    MultiSwapRecipientView(address: self.recipient, token: self.token1) { [weak self] recipient in
                        self?.recipient = recipient
                        self?.refreshSubject.send()
                    }
                }
            }
        )

        return menuItems
    }

    var refreshPublisher: AnyPublisher<Void, Never>? {
        refreshSubject.eraseToAnyPublisher()
    }

    func sendData(transactionSettings: TransactionSettings?) async throws -> ISendData {
        let quote: LiquidityAddFinalQuote
        if manualAmountOutMode {
            quote = try await provider.confirmationQuote(
                token0: token0, token1: token1, amount0: amount0, amount1: amount1, transactionSettings: transactionSettings
            )
        } else {
            quote = try await provider.confirmationQuote(
                token0: token0, token1: token1, amount0: amount0, transactionSettings: transactionSettings
            )
        }
        return SendData(token0: token0, token1: token1, amount0: amount0, quote: quote, otherSections: [])
    }

    func send(data: ISendData) async throws {
        guard let data = data as? SendData else {
            throw SendError.invalidData
        }

        if let quote = data.quote as? EvmLiquidityAddFinalQuote {
            guard let transactionData = quote.transactionData else {
                throw SendError.invalidTransactionData
            }

            guard let gasLimit = quote.evmFeeData?.surchargedGasLimit else {
                throw SendError.noGasLimit
            }

            guard let gasPrice = quote.gasPrice else {
                throw SendError.noGasPrice
            }

            guard let evmKitWrapper = try evmBlockchainManager.evmKitManager(blockchainType: token1.blockchainType).evmKitWrapper else {
                throw SendError.noEvmKitWrapper
            }

            _ = try await evmKitWrapper.send(
                transactionData: transactionData,
                gasPrice: gasPrice,
                gasLimit: gasLimit,
                privateSend: mevProtectionHelper.isActive,
                nonce: quote.nonce
            )
        }

        if !walletManager.activeWallets.contains(where: { $0.token == token1 }), let activeAccount = accountManager.activeAccount {
            let wallet = Wallet(token: token1, account: activeAccount)
            walletManager.save(wallets: [wallet])
        }
    }
}

extension LiquidityAddSendHandler {
    class SendData: ISendData {
        let token0: Token
        let token1: Token
        let amount0: Decimal
//        let amount1: Decimal
        let quote: LiquidityAddFinalQuote
        let otherSections: [SendDataSection]

        init(token0: Token, token1: Token, amount0: Decimal, /*amount1: Decimal,*/ quote: LiquidityAddFinalQuote, otherSections: [SendDataSection]) {
            self.token0 = token0
            self.token1 = token1
            self.amount0 = amount0
//            self.amount1 = amount1
            self.quote = quote
            self.otherSections = otherSections
        }

        var feeData: FeeData? {
            quote.feeData
        }

        var canSend: Bool {
            quote.canSwap
        }

        var rateCoins: [Coin] {
            [token0.coin, token1.coin]
        }

        var customSendButtonTitle: String? {
            nil
        }

        func cautions(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [CautionNew] {
            quote.cautions(baseToken: baseToken) + priceImpactCautions(baseToken: baseToken, currency: currency, rates: rates)
        }

        private func priceImpact(baseToken _: Token, currency _: Currency, rates: [String: Decimal]) -> Decimal? {
            let fiatAmountIn = rates[token0.coin.uid].map { amount0 * $0 }
            let fiatAmountOut = rates[token1.coin.uid].map { quote.amountOut * $0 }

            if let fiatAmountIn, let fiatAmountOut, fiatAmountIn != 0, fiatAmountIn > fiatAmountOut {
                let priceImpact = (fiatAmountOut * 100 / fiatAmountIn) - 100
                return priceImpact
            }

            return nil
        }

        private func priceImpactCautions(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [CautionNew] {
            var cautions = [CautionNew]()

            if let priceImpact = priceImpact(baseToken: baseToken, currency: currency, rates: rates) {
                let level = MultiSwapViewModel.PriceImpactLevel(priceImpact: abs(priceImpact))

                switch level {
                case .warning: cautions.append(.init(title: "swap.price_impact".localized, text: "swap.confirmation.impact_high".localized(PriceImpact.display(value: priceImpact)), type: .warning))
                case .forbidden: cautions.append(.init(title: "swap.price_impact".localized, text: "swap.confirmation.impact_too_high".localized(PriceImpact.display(value: priceImpact)), type: .error))
                default: ()
                }
            }

            return cautions
        }

        func flowSection(baseToken _: Token, currency: Currency, rates: [String: Decimal]) -> SendDataSection {
            .init([
                .amount(
                    token: token0,
                    appValueType: .regular(appValue: AppValue(token: token0, value: amount0)),
                    currencyValue: rates[token0.coin.uid].map { CurrencyValue(currency: currency, value: amount0 * $0) },
                ),
                .amount(
                    token: token1,
                    appValueType: .regular(appValue: AppValue(token: token1, value: quote.amountOut)),
                    currencyValue: rates[token1.coin.uid].map { CurrencyValue(currency: currency, value: quote.amountOut * $0) },
                ),
            ], isFlow: true)
        }

        func sections(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [SendDataSection] {
            var fields: [SendField] = []

            fields.append(
                .price(
                    title: "swap.price".localized,
                    tokenA: token0,
                    tokenB: token1,
                    amountA: amount0,
                    amountB: quote.amountOut
                )
            )

            if let priceImpact = priceImpact(baseToken: baseToken, currency: currency, rates: rates) {
                let level = MultiSwapViewModel.PriceImpactLevel(priceImpact: abs(priceImpact))

                switch level {
                case .normal, .warning, .forbidden:
                    fields.append(
                        .simpleValue(
                            title: SendField.InformedTitle("swap.price_impact".localized, info: InfoDescription(
                                title: "swap.price_impact".localized,
                                description: "swap.price_impact.info".localized
                            )),
                            value: ComponentText(text: PriceImpact.display(value: priceImpact), colorStyle: level.valueLevel.colorStyle)
                        )
                    )
                default: ()
                }
            }

            fields.append(contentsOf: quote.fields(
                tokenIn: token0,
                tokenOut: token1,
                baseToken: baseToken,
                currency: currency,
                tokenInRate: rates[token0.coin.uid],
                tokenOutRate: rates[token1.coin.uid],
                baseTokenRate: rates[baseToken.coin.uid]
            ))

            return [
                flowSection(baseToken: baseToken, currency: currency, rates: rates),
                .init(fields, isMain: false),
            ] + otherSections
        }
    }

    enum SendError: Error {
        case invalidData
        case invalidTransactionData
        case noGasLimit
        case noGasPrice
        case noEvmKitWrapper
        case noTronKitWrapper
        case noBitcoinAdapter
        case noSendParameters
        case noZcashAdapter
        case noMoneroAdapter
        case noProposal
        case noTonAdapter
        case noActiveAccount

        case unsupportedtoken0
        case unsupportedtoken1
        case noCommonProvider
        case noRoutes
        case noTransactionData
        case noJettonAdapter
        case noInboundAddress
    }
}

extension LiquidityAddSendHandler {
    static func instance(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider, v3TickType: LiquidityTickType? = nil, manualAmountOutMode: Bool = false) -> LiquidityAddSendHandler? {
        let baseToken: Token?

        switch token0.type {
        case .native, .derived, .addressType:
            baseToken = token0
        case .eip20, .spl, .jetton, .stellar:
            baseToken = try? Core.shared.marketKit.token(query: TokenQuery(blockchainType: token0.blockchainType, tokenType: .native))
        case .unsupported:
            baseToken = nil
        }

        guard let baseToken else {
            return nil
        }

        return LiquidityAddSendHandler(baseToken: baseToken, token0: token0, token1: token1, amount0: amount0, amount1: amount1, provider: provider, v3TickType: v3TickType, manualAmountOutMode: manualAmountOutMode)
    }
}
