import BigInt
import Eip20Kit
import EvmKit
import Foundation
import MarketKit

class LiquidityAddSendHandler {
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let accountManager = Core.shared.accountManager
    private let walletManager = Core.shared.walletManager

    let baseToken: Token
    let token0: Token
    let token1: Token
    let amount0: Decimal
    let amount1: Decimal
    let provider: ILiquidityAddProvider

    init(baseToken: Token, token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider) {
        self.baseToken = baseToken
        self.token0 = token0
        self.token1 = token1
        self.amount0 = amount0
        self.amount1 = amount1
        self.provider = provider
    }
}

extension LiquidityAddSendHandler: ISendHandler {
    var syncingText: String? {
        "swap.confirmation.quoting".localized
    }

    var expirationDuration: Int? {
        15
    }

    func sendData(transactionSettings: TransactionSettings?) async throws -> ISendData {
        let quote = try await provider.confirmationQuote(
            token0: token0,
            token1: token1,
            amount0: amount0,
            transactionSettings: transactionSettings
        )

        let otherSections = provider.otherSections(
            token0: token0,
            token1: token1,
            amount0: amount0,
            transactionSettings: transactionSettings
        )

        return SendData(token0: token0, token1: token1, amount0: amount0, amount1: amount1, quote: quote, otherSections: otherSections)
    }

    func send(data: ISendData) async throws {
        guard let data = data as? SendData else {
            throw SendError.invalidData
        }

        try await provider.swap(token0: token0, token1: token1, amount0: amount0, quote: data.quote)

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
        let amount1: Decimal
        let quote: ILiquidityAddConfirmationQuote
        let otherSections: [SendDataSection]

        init(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, quote: ILiquidityAddConfirmationQuote, otherSections: [SendDataSection]) {
            self.token0 = token0
            self.token1 = token1
            self.amount0 = amount0
            self.amount1 = amount1
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

        func cautions(baseToken: Token) -> [CautionNew] {
            quote.cautions(baseToken: baseToken)
        }

        func sections(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [SendDataSection] {
            var sections: [SendDataSection] = [
                .init([
                    .amount(
                        title: "swap.you_pay".localized,
                        token: token0,
                        appValueType: .regular(appValue: AppValue(token: token0, value: amount0)),
                        currencyValue: rates[token0.coin.uid].map { CurrencyValue(currency: currency, value: amount0 * $0) },
                        type: .neutral
                    ),
                    .amount(
                        title: "swap.you_pay".localized,
                        token: token1,
                        appValueType: .regular(appValue: AppValue(token: token1, value: amount1)),
                        currencyValue: rates[token1.coin.uid].map { CurrencyValue(currency: currency, value: amount1 * $0) },
                        type: .neutral
                    ),
//                    .amount(
//                        title: "swap.you_get".localized,
//                        token: ,
//                        appValueType: .regular(appValue: AppValue(token: token1, value: quote.amountOut)),
//                        currencyValue: rates[token1.coin.uid].map { CurrencyValue(currency: currency, value: quote.amountOut * $0) },
//                        type: .incoming
//                    ),
                ]),
            ]

            var priceSection: [SendField] = [
                .price(
                    title: "swap.price".localized,
                    tokenA: token0,
                    tokenB: token1,
                    amountA: amount0,
                    amountB: quote.amountOut
                ),
            ]

            let priceSectionFields = quote.priceSectionFields(
                token0: token0,
                token1: token1,
                baseToken: baseToken,
                currency: currency,
                token0Rate: rates[token0.coin.uid],
                token1Rate: rates[token1.coin.uid],
                baseTokenRate: rates[baseToken.coin.uid]
            )

            if !priceSectionFields.isEmpty {
                priceSection.append(contentsOf: priceSectionFields)
            }

            sections.append(.init(priceSection))

            sections.append(contentsOf: quote.otherSections(
                token0: token0,
                token1: token1,
                baseToken: baseToken,
                currency: currency,
                token0Rate: rates[token0.coin.uid],
                token1Rate: rates[token1.coin.uid],
                baseTokenRate: rates[baseToken.coin.uid]
            ))

            sections.append(contentsOf: otherSections)

            return sections
        }
    }

    enum SendError: Error {
        case invalidData
    }
}

extension LiquidityAddSendHandler {
    static func instance(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider) -> LiquidityAddSendHandler? {
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

        return LiquidityAddSendHandler(baseToken: baseToken, token0: token0, token1: token1, amount0: amount0, amount1: amount1, provider: provider)
    }
}

