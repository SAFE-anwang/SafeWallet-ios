import BigInt
import EvmKit
import Foundation
import HsExtensions
import MarketKit
import SwiftUI

class ManualUniswapV2LiquidityAddProvider: BaseEvmLiquidityAddProvider {
    private let evmFeeEstimator = EvmFeeEstimator()
    private let allowanceHelper = LiquidityAddAllowanceHelper()

    private let _id: String
    private let _name: String
    private let _icon: String

    private let token1Amount: Decimal
    private let supportsHandler: (Token, Token) -> Bool
    private let spenderAddressProvider: (Chain) throws -> EvmKit.Address

    init(id: String, name: String, icon: String, storage: MultiSwapSettingStorage, token1Amount: Decimal, supports: @escaping (Token, Token) -> Bool, spenderAddress: @escaping (Chain) throws -> EvmKit.Address) {
        _id = id
        _name = name
        _icon = icon
        self.token1Amount = token1Amount
        supportsHandler = supports
        spenderAddressProvider = spenderAddress

        super.init(storage: storage)
    }

    override var id: String {
        _id
    }

    override var name: String {
        _name
    }

    override var icon: String {
        _icon
    }

    override func supports(token0: Token, token1: Token) -> Bool {
        supportsHandler(token0, token1)
    }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        try spenderAddressProvider(chain)
    }

    override func quote(token0: Token, token1: Token, amount0: Decimal) async throws -> ILiquidityAddQuote {
        let chain = try evmBlockchainManager.chain(blockchainType: token0.blockchainType)
        let spenderAddress = try spenderAddress(chain: chain)

        async let allowanceState0 = allowanceHelper.allowanceState(spenderAddress: .init(raw: spenderAddress.eip55), token: token0, amount: amount0)
        async let allowanceState1 = allowanceHelper.allowanceState(spenderAddress: .init(raw: spenderAddress.eip55), token: token1, amount: token1Amount)

        return try await ManualLiquidityAddQuote(
            amountOut: token1Amount,
            allowanceState0: allowanceState0,
            allowanceState1: allowanceState1
        )
    }

    override func confirmationQuote(token0: Token, token1: Token, amount0: Decimal, transactionSettings: TransactionSettings?) async throws -> ILiquidityAddConfirmationQuote {
        let blockchainType = token0.blockchainType
        let chain = try evmBlockchainManager.chain(blockchainType: blockchainType)

        let recipient = storage.recipient(blockchainType: blockchainType)
        let slippage: Decimal = storage.value(for: MultiSwapSettingStorage.LegacySetting.slippage) ?? MultiSwapSlippage.default

        let gasPriceData = transactionSettings?.gasPriceData
        var txData: TransactionData?
        var evmFeeData: EvmFeeData?
        var transactionError: Error?

        if let evmKitWrapper = try evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper, let gasPriceData {
            do {
                let receiveAddress = evmKitWrapper.evmKit.receiveAddress
                let transactionData = try transactionData(token0: token0, token1: token1, amount0: amount0, amount1: token1Amount, receiveAddress: receiveAddress, chain: chain, recipient: recipient, slippage: slippage)
                txData = transactionData
                evmFeeData = try await evmFeeEstimator.estimateFee(evmKitWrapper: evmKitWrapper, transactionData: transactionData, gasPriceData: gasPriceData)
            } catch {
                transactionError = error
            }
        }

        return ManualUniswapV2LiquidityAddConfirmationQuote(
            token1Amount: token1Amount,
            recipient: recipient,
            slippage: slippage,
            deadline: Constants.getDeadLine(),
            transactionData: txData,
            transactionError: transactionError,
            gasPrice: gasPriceData?.userDefined,
            evmFeeData: evmFeeData,
            nonce: transactionSettings?.nonce
        )
    }

    override func settingsView(token0 _: Token, token1: Token, quote _: ILiquidityAddQuote, onChangeSettings: @escaping () -> Void) -> AnyView {
        let view = ThemeNavigationStack {
            RecipientAndSlippageMultiSwapSettingsView(tokenOut: token1, storage: storage, slippageMode: .adjustable, onChangeSettings: onChangeSettings)
        }

        return AnyView(view)
    }

    override func settingView(settingId: String, tokenOut: Token, onChangeSetting: @escaping () -> Void) -> AnyView {
        if settingId == MultiSwapMainField.slippageSettingId {
            let view = ThemeNavigationStack {
                RecipientAndSlippageMultiSwapSettingsView(tokenOut: tokenOut, storage: storage, slippageMode: .adjustable, onChangeSettings: onChangeSetting)
            }
            return AnyView(view)
        }

        return AnyView(EmptyView())
    }

    override func swap(token0: Token, token1 _: Token, amount0 _: Decimal, quote: ILiquidityAddConfirmationQuote) async throws {
        guard let quote = quote as? ManualUniswapV2LiquidityAddConfirmationQuote else {
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

        try await send(
            blockchainType: token0.blockchainType,
            transactionData: transactionData,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            nonce: quote.nonce
        )
    }

    private func transactionData(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, receiveAddress: EvmKit.Address, chain: Chain, recipient: Address?, slippage: Decimal) throws -> TransactionData {
        let routerAddress = try spenderAddress(chain: chain)
        let toAddress = try (recipient.map { try EvmKit.Address(hex: $0.raw) } ?? receiveAddress)

        let min0 = (amount0 * (1 - slippage / 100)).rounded(decimal: token0.decimals)
        let min1 = (amount1 * (1 - slippage / 100)).rounded(decimal: token1.decimals)

        guard let amount0Raw = token0.rawAmount(amount0), let amount1Raw = token1.rawAmount(amount1), let min0Raw = token0.rawAmount(min0), let min1Raw = token1.rawAmount(min1) else {
            throw SwapError.invalidAmount
        }

        let deadline = Constants.getDeadLine()

        switch (token0.type, token1.type) {
        case (.native, let .eip20(addressString)):
            let tokenAddress = try EvmKit.Address(hex: addressString)
            let method = AddLiquidityEthMethod(token: tokenAddress, amountTokenDesired: amount1Raw, amountTokenMin: min1Raw, amountEthMin: min0Raw, to: toAddress, deadline: deadline)
            return TransactionData(to: routerAddress, value: amount0Raw, input: method.encodedABI())
        case (let .eip20(addressString), .native):
            let tokenAddress = try EvmKit.Address(hex: addressString)
            let method = AddLiquidityEthMethod(token: tokenAddress, amountTokenDesired: amount0Raw, amountTokenMin: min0Raw, amountEthMin: min1Raw, to: toAddress, deadline: deadline)
            return TransactionData(to: routerAddress, value: amount1Raw, input: method.encodedABI())
        case (let .eip20(address0), let .eip20(address1)):
            let tokenA = try EvmKit.Address(hex: address0)
            let tokenB = try EvmKit.Address(hex: address1)
            let method = AddLiquidityMethod(tokenA: tokenA, tokenB: tokenB, amountADesired: amount0Raw, amountBDesired: amount1Raw, amountAMin: min0Raw, amountBMin: min1Raw, to: toAddress, deadline: deadline)
            return TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        default:
            throw SwapError.invalidToken
        }
    }
}

extension ManualUniswapV2LiquidityAddProvider {
    enum SwapError: Error {
        case invalidToken
        case invalidAmount
        case invalidQuote
        case noTransactionData
        case noGasPrice
        case noGasLimit
    }
}

class ManualLiquidityAddQuote: BaseEvmLiquidityAddQuote {
    let amount1: Decimal
    let allowanceState0: LiquidityAddAllowanceHelper.AllowanceState
    let allowanceState1: LiquidityAddAllowanceHelper.AllowanceState

    init(amountOut: Decimal, allowanceState0: LiquidityAddAllowanceHelper.AllowanceState, allowanceState1: LiquidityAddAllowanceHelper.AllowanceState) {
        amount1 = amountOut
        self.allowanceState0 = allowanceState0
        self.allowanceState1 = allowanceState1

        let allowanceState: LiquidityAddAllowanceHelper.AllowanceState
        if allowanceState0.customButtonState != nil {
            allowanceState = allowanceState0
        } else if allowanceState1.customButtonState != nil {
            allowanceState = allowanceState1
        } else {
            allowanceState = .allowed
        }

        super.init(allowanceState: allowanceState)
    }

    override var amountOut: Decimal {
        amount1
    }

    override func fields(token0: Token, token1: Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?) -> [MultiSwapMainField] {
        var fields = [MultiSwapMainField]()
        fields.append(contentsOf: allowanceState0.fields())
        fields.append(contentsOf: allowanceState1.fields())
        return fields
    }

    override func cautions() -> [CautionNew] {
        allowanceState0.cautions() + allowanceState1.cautions()
    }
}

class ManualUniswapV2LiquidityAddConfirmationQuote: BaseEvmLiquidityAddConfirmationQuote {
    let token1Amount: Decimal
    let recipient: Address?
    let slippage: Decimal
    let deadline: BigUInt
    let transactionData: TransactionData?
    let transactionError: Error?

    init(token1Amount: Decimal, recipient: Address?, slippage: Decimal, deadline: BigUInt, transactionData: TransactionData?, transactionError: Error?, gasPrice: GasPrice?, evmFeeData: EvmFeeData?, nonce: Int?) {
        self.token1Amount = token1Amount
        self.recipient = recipient
        self.slippage = slippage
        self.deadline = deadline
        self.transactionData = transactionData
        self.transactionError = transactionError

        super.init(gasPrice: gasPrice, evmFeeData: evmFeeData, nonce: nonce)
    }

    override var amountOut: Decimal {
        token1Amount
    }

    override var canSwap: Bool {
        super.canSwap && transactionData != nil
    }

    override func cautions(baseToken: Token) -> [CautionNew] {
        var cautions = super.cautions(baseToken: baseToken)

        if let transactionError {
            cautions.append(caution(transactionError: transactionError, feeToken: baseToken))
        }

        return cautions
    }

    override func priceSectionFields(token0: Token, token1: Token, baseToken _: Token, currency: Currency, token0Rate _: Decimal?, token1Rate: Decimal?, baseTokenRate _: Decimal?) -> [SendField] {
        var fields = [SendField]()

        if let recipient {
            fields.append(.recipient(recipient.title, blockchainType: token1.blockchainType))
        }

        fields.append(.slippage(slippage))

        let deadlineMinutes = Decimal(Constants.deadLine).description
//        fields.append(.deadline("swap.advanced_settings.deadline_minute".localized(deadlineMinutes)))

        let minToken1 = token1Amount * (1 - slippage / 100)
        fields.append(
            .value(
                title: "swap.confirmation.minimum_received".localized,
                description: nil,
                appValue: AppValue(token: token1, value: minToken1),
                currencyValue: token1Rate.map { CurrencyValue(currency: currency, value: minToken1 * $0) },
                formatFull: true
            )
        )

        return fields
    }
}
