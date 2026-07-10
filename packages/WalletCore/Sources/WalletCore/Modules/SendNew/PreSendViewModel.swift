import Combine
import SwiftUI
import Foundation
import MarketKit
import EvmKit
import BigInt

public class PreSendViewModel: ObservableObject {
    private let wallet: Wallet
    let resolvedAddress: ResolvedAddress
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let walletManager = Core.shared.walletManager
    private let adapterManager = Core.shared.adapterManager
    private let decimalParser = AmountDecimalParser()

    private var cancellables = Set<AnyCancellable>()

    @Published var currency: Currency
    private let customDecimals: Int?
    public var timeLockItems: [TimeLockService.Item] {
        TimeLockService.Item.allCases
    }
    public var selectedTimeLock: TimeLockService.Item = .none {
        didSet {
            allowanceHandler.resetState()
            sendData = nil
            cautions = []
            syncSendData()
        }
    }

    public var minTimeLockCoinValue: Decimal {
        1
    }

    public var isSupportedTimeLockToken: Bool {
        if token.isSafe4Native || token.isSafe4ETH || token.isSafe4BSC || token.isSafe4POL || token.isSafe4SRC {
            return true
        } else if token.coin.uid.isSafeFourCustomCoin, let _ = SRC20SyncManager.logo(coinUid: token.coin.uid.lowercased()) {
            return true
        }
        return false
    }

    public var amount: Decimal? {
        didSet {
            syncFiatAmount()
            syncSendData()

            var amount = decimalParser.parseAnyDecimal(from: amountString)

            if amount == 0 {
                amount = nil
            }

            if amount != self.amount {
                amountString = self.amount?.description ?? ""
            }
        }
    }

    @Published public var amountString: String = "" {
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

    @Published public private(set) var adapterState: AdapterState?
    @Published public private(set) var availableBalance: Decimal?
    @Published var hasMemo = false

    private var enteringFiat = false

    @Published var memo: String = "" {
        didSet {
            syncSendData()
        }
    }

    var handler: IPreSendHandler?
    @Published public private(set) var sendData: ExtendedSendData?
    @Published var cautions = [CautionNew]()
    var allowanceHandler: PreSendAllowanceHandler

    public init(wallet: Wallet, handler: IPreSendHandler?, resolvedAddress: ResolvedAddress, amount: Decimal?, memo: String?, customDecimals: Int? = nil) {
        self.wallet = wallet
        self.handler = handler
        self.resolvedAddress = resolvedAddress
        self.customDecimals = customDecimals

        self.allowanceHandler = PreSendAllowanceHandler(token: wallet.token)
        currency = currencyManager.baseCurrency

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

public extension PreSendViewModel {
    var token: Token {
        wallet.token
    }

    internal var title: String {
        handler?.title(token.coin.code) ?? "send.send".localized
    }

    internal func syncSendData() {
        guard let amount else {
            sendData = nil
            return
        }

        // guard case let .valid(address) = addressState else {
        //     sendData = nil
        //     return
        // }

        guard let handler else {
            sendData = nil
            return
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
        let memo = hasMemo && !trimmedMemo.isEmpty ? trimmedMemo : nil


        if selectedTimeLock != .none {
            guard amount >= 1 else {
                sendData = nil
                return
            }
        }

        synceTimeLock()

        if let sendHandler = handler as? EvmPreSendHandler, !token.type.isNative, selectedTimeLock != .none {
            if let availableBalance {
                allowanceHandler.getAllowanceState(amount: amount, availableBalance: availableBalance, onSuccess: { [weak self] state in
                    self?.synceSendDataResult(handler: handler, amount: amount, memo: memo)
                })
            }
        }else {
            synceSendDataResult(handler: handler, amount: amount, memo: memo)
        }
    }

    private func synceSendDataResult(handler: IPreSendHandler, amount: Decimal, memo: String?) {
        let result = handler.sendData(amount: amount, address: resolvedAddress.address, memo: memo)
        switch result {
        case let .valid(sendData):
            DispatchQueue.main.async {
                self.sendData = ExtendedSendData(sendData: sendData, address: self.resolvedAddress.address)
                self.cautions = []
            }
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

        amount = (availableBalance * Decimal(percent) / 100).rounded(decimal: customDecimals ?? token.decimals)
    }

    func clearAmountIn() {
        enteringFiat = false
        amountString = ""
        amount = nil
    }
}

extension PreSendViewModel {
    public struct ExtendedSendData {
        public let sendData: SendData
        public let address: String?
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

extension PreSendViewModel {
    func synceTimeLock() {
        switch handler  {
        case let handler as EvmPreSendHandler:
            var timeLock: TimeLock?

            if selectedTimeLock == .none {
                timeLock = nil
            } else if let days = selectedTimeLock.days {
                guard let amount, let evmAmount = BigUInt(amount.hs.roundedString(decimal: token.decimals)) else {
                    return
                }
                if token.coin.uid == safe4CoinUid, token.type == .native {
                    timeLock = TimeLock(token: .native, lockDays: days, value: evmAmount)
                } else if token.coin.uid.isSafeFourCustomCoin, let _ = SRC20SyncManager.logo(coinUid: token.coin.uid.lowercased()) {
                    if case let .eip20(address) = token.type {
                        timeLock = TimeLock(token: .src20(contract: try! EvmKit.Address(hex: address)), lockDays: days, value: evmAmount)
                    }
                }
            }
            handler.timeLock = timeLock
        default: ()
        }
    }
}
