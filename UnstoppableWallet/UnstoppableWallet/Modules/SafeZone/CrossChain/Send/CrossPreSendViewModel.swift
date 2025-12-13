import Combine
import SwiftUI
import Foundation
import MarketKit
import EvmKit
import RxSwift

class CrossPreSendViewModel: ObservableObject {
    private let wallet: Wallet
    let resolvedAddress: ResolvedAddress
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let walletManager = Core.shared.walletManager
    private let adapterManager = Core.shared.adapterManager
    private let decimalParser = AmountDecimalParser()
    private let parserChain: AddressParserChain

    private var cancellables = Set<AnyCancellable>()
    private var disposeBag = DisposeBag()
    
    @Published var currency: Currency
    
    @Published var address: String = "" {
        didSet {
            if address.count > 0 {
                validateAddress(address: address)
            }else {
                addressCautionState = .none
            }
            syncSendData()
        }
    }
    @Published var addressResult: AddressInput.Result = .idle
    @Published var addressCautionState: CautionState = .none
    var borderColor: Color {
        switch addressResult {
        case .invalid: return .themeLucian
        default: return .themeBlade
        }
    }
    
    var amount: Decimal? {
        didSet {
            syncFiatAmount()
            syncSendData()

            let amount = decimalParser.parseAnyDecimal(from: amountString)

            if amount != self.amount {
                amountString = self.amount?.description ?? ""
            }
        }
    }

    @Published var amountString: String = "" {
        didSet {
            var amount = decimalParser.parseAnyDecimal(from: amountString)

            if amount == 0 {
                amount = nil
            }

            guard amount != self.amount else {
                return
            }

            enteringFiat = false

            self.amount = amount
        }
    }

    @Published var fiatAmount: Decimal? {
        didSet {
            syncAmount()

            let amount = decimalParser.parseAnyDecimal(from: fiatAmountString)?.rounded(decimal: 2)

            if amount != fiatAmount {
                fiatAmountString = fiatAmount?.description ?? ""
            }
        }
    }

    @Published var fiatAmountString: String = "" {
        didSet {
            let amount = decimalParser.parseAnyDecimal(from: fiatAmountString)?.rounded(decimal: 2)

            guard amount != fiatAmount else {
                return
            }

            enteringFiat = true

            fiatAmount = amount
        }
    }

    @Published var coinPrice: CoinPrice? {
        didSet {
            syncFiatAmount()
        }
    }

    @Published var adapterState: AdapterState?
    @Published var availableBalance: Decimal?
    @Published var hasMemo = false

    private var enteringFiat = false

    @Published var memo: String = "" {
        didSet {
            syncSendData()
        }
    }

    var handler: IPreSendHandler?
    let crossChainHandler: ICrossChainHandler
    @Published var sendData: ExtendedSendData?
    @Published var cautions = [CautionNew]()
    
    init(handler: IPreSendHandler?, crossChainHandler: ICrossChainHandler, resolvedAddress: ResolvedAddress, amount: Decimal?, memo: String?) {
        self.wallet = crossChainHandler.wallet
        self.handler = handler
        self.crossChainHandler = crossChainHandler
        self.resolvedAddress = resolvedAddress
        self.parserChain = AddressParserFactory.parserChain(blockchainType: crossChainHandler.receiverBlockchainType)
        currency = currencyManager.baseCurrency
        address = Core.shared.adapterManager.depositAdapter(for: crossChainHandler.wallet)?.receiveAddress.address ?? ""
        defer {
            if let amount {
                self.amount = amount
            }
            if let memo {
                self.memo = memo
            }
        }

        currencyManager.$baseCurrency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currency = $0 }
            .store(in: &cancellables)

        coinPrice = marketKit.coinPrice(coinUid: wallet.coin.uid, currencyCode: currency.code)
        marketKit.coinPricePublisher(coinUid: wallet.coin.uid, currencyCode: currency.code)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] price in self?.coinPrice = price }
            .store(in: &cancellables)

        if let handler {
            adapterState = handler.state
            availableBalance = handler.balance
            hasMemo = handler.hasMemo(address: resolvedAddress.address)

            handler.statePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.adapterState = $0 }
                .store(in: &cancellables)

            handler.balancePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.availableBalance = $0 }
                .store(in: &cancellables)

            handler.settingsModifiedPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncSendData() }
                .store(in: &cancellables)
        }

        syncFiatAmount()
    }

    private func syncAmount() {
        guard enteringFiat else {
            return
        }

        guard let coinPrice, let fiatAmount else {
            amount = nil
            return
        }

        amount = fiatAmount / coinPrice.value
    }

    private func syncFiatAmount() {
        guard !enteringFiat else {
            return
        }

        guard let coinPrice, let amount else {
            fiatAmount = nil
            return
        }

        fiatAmount = (amount * coinPrice.value).rounded(decimal: 2)
    }

    private func syncHasMemo() {
        guard let handler else {
            hasMemo = false
            return
        }

        hasMemo = handler.hasMemo(address: resolvedAddress.address)
    }
}

extension CrossPreSendViewModel {
    var token: Token {
        wallet.token
    }

    var title: String {
        crossChainHandler.navTitle
    }

    func syncSendData() {
        guard let amount, amount >= crossChainHandler.minAmount  else {
            sendData = nil
            return
        }

         guard case let .valid(address) = addressResult else {
             sendData = nil
             return
         }

        guard let handler else {
            sendData = nil
            return
        }
        
//        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
//        let memo = hasMemo && !trimmedMemo.isEmpty ? trimmedMemo : nil
        let result = crossChainHandler.sendData(amount: amount, address: address.address.raw)

        switch result {
        case let .valid(sendData):
            self.sendData = ExtendedSendData(sendData: sendData, address: resolvedAddress.address)
            cautions = []
        case let .invalid(cautions):
            sendData = nil
            self.cautions = cautions
        }
    }

    func setAmountIn(percent: Int) {
        guard let availableBalance else {
            return
        }

        enteringFiat = false

        amount = (availableBalance * Decimal(percent) / 100).rounded(decimal: token.decimals)
    }

    func clearAmountIn() {
        enteringFiat = false
        amount = nil
    }
}
extension CrossPreSendViewModel {
    struct ExtendedSendData {
        let sendData: SendData
        let address: String?
    }

    // TODO: remove this, not needed for new send
    enum Mode {
        case regular
        case prefilled(address: String, amount: Decimal?)
        case predefined(address: String)

        var amount: Decimal? {
            switch self {
            case let .prefilled(_, amount): return amount
            default: return nil
            }
        }
    }
}

// validate address
extension CrossPreSendViewModel {
    private func validateAddress(address: String) {
        parserChain
            .handle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .observeOn(MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] in self?.sync($0, uri: nil) },
                onError: { [weak self] in self?.sync($0, text: address) }
            )
            .disposed(by: disposeBag)
    }

    private func sync(_ address: Address?, uri: AddressUri?) {
        guard let address else {
            addressResult = .idle
            return
        }

        addressResult = .valid(.init(address: address, uri: uri))
        addressCautionState = .none
    }

    private func sync(_ error: Error, text: String) {
        addressResult = .invalid(.init(text: text, error: error))
        let caution = Caution(text: "watch_address.error.not_supported".localized, type: .error)
        addressCautionState = .caution(caution)
    }
}
