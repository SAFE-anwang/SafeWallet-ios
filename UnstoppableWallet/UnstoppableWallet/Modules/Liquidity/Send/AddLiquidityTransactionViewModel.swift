import Foundation
import RxSwift
import RxCocoa
import EvmKit
import BigInt
import UniswapKit
import OneInchKit
import Eip20Kit
import NftKit
import MarketKit
import HsExtensions

class AddLiquidityTransactionViewModel {
    private let disposeBag = DisposeBag()

    private let service: IAddLiquidityTransactionService
    private let coinServiceFactory: EvmCoinServiceFactory
    private let cautionsFactory: SendEvmCautionsFactory
    private let evmLabelManager: EvmLabelManager
    private let contactLabelService: ContactLabelService

    private let sectionViewItemsRelay = BehaviorRelay<[SectionViewItem]>(value: [])

    private let sendEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let cautionsRelay = BehaviorRelay<[TitledCaution]>(value: [])

    private let sendingRelay = PublishRelay<()>()
    private let sendSuccessRelay = PublishRelay<Data>()
    private let sendFailedRelay = PublishRelay<String>()
        
    private let currencyManager: CurrencyManager
    private let marketKit: MarketKit.Kit
    private let chainToken: MarketKit.Token
    
    private var rate: CurrencyValue? {
        let baseCurrency = currencyManager.baseCurrency
        let coinPrice = marketKit.coinPrice(coinUid: chainToken.coin.uid, currencyCode: baseCurrency.code)
        if let value = coinPrice?.value {
            return CurrencyValue(currency: baseCurrency, value: value)
        }
        return nil
    }

    init(service: IAddLiquidityTransactionService, coinServiceFactory: EvmCoinServiceFactory, cautionsFactory: SendEvmCautionsFactory, evmLabelManager: EvmLabelManager, contactLabelService: ContactLabelService, marketKit: MarketKit.Kit, currencyManager: CurrencyManager, chainToken: MarketKit.Token) {
        self.service = service
        self.coinServiceFactory = coinServiceFactory
        self.cautionsFactory = cautionsFactory
        self.evmLabelManager = evmLabelManager
        self.contactLabelService = contactLabelService
        self.marketKit = marketKit
        self.currencyManager = currencyManager
        
        self.chainToken = chainToken
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        subscribe(disposeBag, service.sendStateObservable) { [weak self] in self?.sync(sendState: $0) }

        subscribe(disposeBag, contactLabelService.stateObservable) { [weak self] _ in
            self?.reSyncServiceState()
        }

        sync(state: service.state)
        sync(sendState: service.sendState)
        
    }
    
    private func reSyncServiceState() {
        sync(state: service.state)
    }

    private func sync(state: AddLiquidityTransactionService.State) {
        switch state {
        case .ready(let warnings):
            cautionsRelay.accept(cautionsFactory.items(errors: [], warnings: warnings, baseCoinService: coinServiceFactory.baseCoinService))
            sendEnabledRelay.accept(true)
        case .notReady(let errors, let warnings):
            cautionsRelay.accept(cautionsFactory.items(errors: errors, warnings: warnings, baseCoinService: coinServiceFactory.baseCoinService))
            sendEnabledRelay.accept(false)
        }

        sectionViewItemsRelay.accept(items(dataState: service.dataState))
    }

    private func formatted(slippage: Decimal) -> String? {
        guard slippage != OneInchSettingsService.defaultSlippage else {
            return nil
        }

        return "\(slippage)%"
    }

    private func sync(sendState: AddLiquidityTransactionService.SendState) {
        switch sendState {
        case .idle: ()
        case .sending: sendingRelay.accept(())
        case .sent(let transactionHash): sendSuccessRelay.accept(transactionHash)
        case .failed(let error): sendFailedRelay.accept(error.convertedError.smartDescription)
        }
    }

    private func items(dataState: AddLiquidityTransactionService.DataState) -> [SectionViewItem] {
        if let items = self.items(transactionData: dataState.transactionData, additionalInfo: dataState.additionalInfo, nonce: dataState.nonce) {
            return items
        }
        return []
    }

    private func items(transactionData: TransactionData?, additionalInfo: SendEvmData.AdditionInfo?, nonce: Int?) -> [SectionViewItem]? {
        
        if let info = additionalInfo?.liquidityInfo ?? additionalInfo?.liquidityV3Info {
            return  addLiquidityItems(
                amountIn0:  info.estimated0,
                amountIn1: info.estimated1,
                tokenIn0: info.token0,
                tokenIn1: info.token1,
                recipient: info.recipientDomain,
                deadline: info.deadline,
                swapInfo: info,
                nonce: nonce
            )
        }
        return nil
    }

    private func amountViewItem(coinService: CoinService, value: BigUInt, type: AmountType) -> ViewItem {
        amountViewItem(coinService: coinService, amountData: coinService.amountData(value: value, sign: type.sign), type: type)
    }

    private func amountViewItem(coinService: CoinService, value: Decimal, type: AmountType) -> ViewItem {
        amountViewItem(coinService: coinService, amountData: coinService.amountData(value: value, sign: type.sign), type: type)
    }

    private func amountViewItem(coinService: CoinService, amountData: AmountData, type: AmountType) -> ViewItem {
        let token = coinService.token

        return .amount(
                iconUrl: token.coin.imageUrl,
                iconPlaceholderImageName: token.placeholderImageName,
                coinAmount: ValueFormatter.instance.formatFull(coinValue: amountData.coinValue) ?? "n/a".localized,
                currencyAmount: amountData.currencyValue.flatMap { ValueFormatter.instance.formatFull(currencyValue: $0) },
                type: type
        )
    }

    private func estimatedAmountViewItem(coinService: CoinService, value: Decimal, type: AmountType) -> ViewItem {
        let token = coinService.token
        let amountData = coinService.amountData(value: value, sign: type.sign)
        let coinAmount = ValueFormatter.instance.formatFull(coinValue: amountData.coinValue) ?? "n/a".localized
        
        return .amount(
                iconUrl: token.coin.imageUrl,
                iconPlaceholderImageName: token.placeholderImageName,
                coinAmount: "\(coinAmount) \("swap.estimate_short".localized)",
                currencyAmount: amountData.currencyValue.flatMap { ValueFormatter.instance.formatFull(currencyValue: $0) },
                type: type
        )
    }


    private func doubleAmountViewItem(coinService: CoinService, title: String, value: BigUInt) -> ViewItem {
        let amountData = coinService.amountData(value: value, sign: .plus)

        return .doubleAmount(
                title: title,
                coinAmount: ValueFormatter.instance.formatFull(coinValue: amountData.coinValue) ?? "n/a".localized,
                currencyAmount: amountData.currencyValue.flatMap { ValueFormatter.instance.formatFull(currencyValue: $0) }
        )
    }
    
    private func addLiquidityItems(amountIn0: Decimal, amountIn1: Decimal, tokenIn0: MarketKit.Token, tokenIn1: MarketKit.Token, recipient: String?, deadline: String?, swapInfo: SendEvmData.LiquidityInfo?, nonce: Int?) -> [SectionViewItem]? {
        let coinServiceIn0 = coinService(token: tokenIn0)

        var sections = [SectionViewItem]()

        var in0ViewItems: [ViewItem] = [
            .subhead(iconName: "arrow_medium_2_up_right_24", title: "swap.you_pay".localized, value: coinServiceIn0.token.coin.name)
        ]

        if let estimatedIn = swapInfo?.estimated0 {
            in0ViewItems.append(estimatedAmountViewItem(coinService: coinServiceIn0, value: estimatedIn, type: .neutral))
        }
        sections.append(SectionViewItem(viewItems: in0ViewItems))

        
        let coinServiceIn1 = coinService(token: tokenIn1)
        var in1ViewItems: [ViewItem] = [
            .subhead(iconName: "arrow_medium_2_up_right_24", title: "swap.you_pay".localized, value: coinServiceIn1.token.coin.name)
        ]
        if let estimatedIn = swapInfo?.estimated1 {
            in1ViewItems.append(estimatedAmountViewItem(coinService: coinServiceIn1, value: estimatedIn, type: .neutral))
        }
        sections.append(SectionViewItem(viewItems: in1ViewItems))

//        let coinServiceOut = coinService(token: tokenIn1)
//        var outViewItems: [ViewItem] = [
//            .subhead(iconName: "arrow_medium_2_down_left_24", title: "swap.you_get".localized, value: coinServiceOut.token.coin.name),
//        ]
//        
//        outViewItems.append(doubleAmountViewItem(coinService: <#T##CoinService#>, title: <#T##String#>, value: <#T##BigUInt#>))
//        sections.append(SectionViewItem(viewItems: outViewItems))
    
        
        var otherViewItems = [ViewItem]()

        if let slippage = swapInfo?.slippage {
            otherViewItems.append(.value(title: "swap.advanced_settings.slippage".localized, value: slippage, type: .regular))
        }
        if let deadline = swapInfo?.deadline {
            otherViewItems.append(.value(title: "swap.advanced_settings.deadline".localized, value: deadline, type: .regular))
        }

        if let addressValue = recipient {
            let addressTitle = swapInfo?.recipientDomain ?? evmLabelManager.addressLabel(address: addressValue)
            let contactData = contactLabelService.contactData(for: addressValue)

            otherViewItems.append(.address(
                    title: "swap.advanced_settings.recipient_address".localized,
                    value: addressValue,
                    valueTitle: addressTitle,
                    contactAddress: contactData.contactAddress
                )
            )
            if let contactName = contactData.name {
                otherViewItems.append(.value(title: "send.confirmation.contact_name".localized, value: contactName, type: .regular))
            }
        }

        if let price = swapInfo?.price {
            otherViewItems.append(.value(title: "swap.price".localized, value: price, type: .regular))
        }
        if let priceImpact = swapInfo?.priceImpact {
            var type: ValueType
            switch priceImpact.level {
            case .normal: type = .warning
            case .warning, .forbidden: type = .alert
            default: type = .regular
            }

            otherViewItems.append(.value(title: "swap.price_impact".localized, value: priceImpact.value, type: type))
        }

        if let nonce = nonce {
            otherViewItems.append(.value(title: "send.confirmation.nonce".localized, value: nonce.description, type: .regular))
        }

        if !otherViewItems.isEmpty {
            sections.append(SectionViewItem(viewItems: otherViewItems))
        }

        return sections
    }

    private func coinService(token: MarketKit.Token) -> CoinService {
        coinServiceFactory.coinService(token: token)
    }

}

extension AddLiquidityTransactionViewModel {

    var sectionViewItemsDriver: Driver<[SectionViewItem]> {
        sectionViewItemsRelay.asDriver()
    }

    var sendEnabledDriver: Driver<Bool> {
        sendEnabledRelay.asDriver()
    }

    var cautionsDriver: Driver<[TitledCaution]> {
        cautionsRelay.asDriver()
    }

    var sendingSignal: Signal<()> {
        sendingRelay.asSignal()
    }

    var sendSuccessSignal: Signal<Data> {
        sendSuccessRelay.asSignal()
    }

    var sendFailedSignal: Signal<String> {
        sendFailedRelay.asSignal()
    }
    
    func send() {
        service.addLiqudity()
    }

}

extension AddLiquidityTransactionViewModel {

    struct SectionViewItem {
        let viewItems: [ViewItem]
    }

    enum ViewItem {
        case subhead(iconName: String, title: String, value: String)
        case amount(iconUrl: String?, iconPlaceholderImageName: String, coinAmount: String, currencyAmount: String?, type: AmountType)
        case nftAmount(iconUrl: String?, iconPlaceholderImageName: String, nftAmount: String, type: AmountType)
        case doubleAmount(title: String, coinAmount: String, currencyAmount: String?)
        case address(title: String, value: String, valueTitle: String?, contactAddress: ContactAddress?)
        case value(title: String, value: String, type: ValueType)
        case input(value: String)
    }

}

