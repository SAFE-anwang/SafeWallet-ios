import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt

class SafeLineLockViewModel: ObservableObject {
    let securityCheckViewModel: AddressSecurityCheckViewModel
    
    @Published var availableBalance: Decimal?
    @Published var currency: Currency
    @Published var sendDisabled: Bool = true
    @Published var lockDes: String?
    @Published var lockTips: String?
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
    @Published var amountCautionState: CautionState = .none
    @Published var lockNumCautionState: CautionState = .none
    @Published var startMonthCautionState: CautionState = .none
    @Published var intervalMonthCautionState: CautionState = .none
    @Published var sendState: SendState = .notReady
    private let wallet: Wallet
    private let adapter: EvmAdapter
    private var enteringFiat = false
    private let decimalParser = AmountDecimalParser()
    private let currencyManager = Core.shared.currencyManager
    private let marketKit = Core.shared.marketKit
    private let parserChain: AddressParserChain
    private(set) var account: Account
    private var disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    @Published private(set) var checkedResolvedAddress: ResolvedAddress?
    @Published private(set) var addressSecurityState: AddressSecurityCheckViewModel.State = .idle

    init(wallet: Wallet, account: Account, adapter: EvmAdapter) {
        self.wallet = wallet
        self.account = account
        self.adapter = adapter
        self.securityCheckViewModel = AddressSecurityCheckViewModel(token: wallet.token)
        self.currency = currencyManager.baseCurrency
        self.availableBalance = adapter.balanceData.available
        self.parserChain = AddressParserFactory.parserChain(blockchainType: wallet.token.blockchainType)
        
        adapter.balanceDataUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe { [weak self] balanceData in
                DispatchQueue.main.async {
                    self?.availableBalance = balanceData.available
                }
            }
            .disposed(by: disposeBag)
        
        let address = adapter.evmKit.receiveAddress.eip55
        self.address = address
        self.addressResult = .valid(.init(address: Address(raw: address), uri: nil))
        
        rate = marketKit.coinPrice(coinUid: wallet.coin.uid, currencyCode: currency.code)?.value
        marketKit.coinPricePublisher( coinUid: wallet.coin.uid, currencyCode: currency.code)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] price in self?.rate = price.value }
            .store(in: &cancellables)

        securityCheckViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.syncFromCheckState(state)
            }
            .store(in: &cancellables)

        syncAddressSecurityState()
    }
    
    var token: Token {
        wallet.token
    }

    var addressIssueTypes: [AddressSecurityIssueType] {
        checkedResolvedAddress?.issueTypes ?? []
    }

    var isAddressChecking: Bool {
        if case .checking = addressSecurityState {
            return true
        }

        return false
    }
    
    var amount: Decimal? {
        didSet {
            syncAmountCautionState()
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
    
    @Published var rate: Decimal? {
        didSet {
            syncFiatAmount()
        }
    }
    
    @Published var lockNum: Int? {
       didSet {
           syncSendData()
       }
    }
    
    @Published var lockNumString: String = "" {
        didSet {
            var lockNum = Int(lockNumString)

            if lockNum == 0 {
                lockNum = nil
            }
            syncLockNumCautionState()
            syncAmountCautionState()
            guard lockNum != self.lockNum else {
                return
            }
            self.lockNum = lockNum
        }
    }
    

    
    @Published var startDate: Date =  Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() {
        didSet {
            syncSendData()
        }
    }
    
    @Published var intervalMonth: Int? {
        didSet {
            syncSendData()
        }
    }
    
    @Published var intervalMonthString: String = "" {
        didSet {
            var intervalMonth = Int(intervalMonthString)

            if intervalMonth == 0 {
                intervalMonth = nil
            }
            syncIntervalMonthCautionState()
            guard intervalMonth != self.intervalMonth else {
                return
            }
            self.intervalMonth = intervalMonth
        }
    }
}

// send
extension SafeLineLockViewModel {
    
    private func syncSendData() {
        lockDes = nil
        lockTips = nil
        sendDisabled = true
        guard case let .valid(result) = addressResult, let to = try? EvmKit.Address(hex: result.address.raw) else { return sendState = .notReady }
        guard let amount, validateAmountIn() == nil else { return sendState = .notReady }
        guard let lockNum, validateLockNum() == nil else { return sendState = .notReady }
        guard startDate != Date() else { return sendState = .notReady }
        guard let intervalMonth, validateIntervalMonth() == nil else { return sendState = .notReady }
                
        let startDay = Int(ceil(startDate.daysAfterDate(Date())))
        let spaceDay = intervalMonth * 30
        let totalLockedAmount = Decimal(lockNum) * amount
        let value = BigUInt((totalLockedAmount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        let sendData = TransactionData(to: to, value: BigUInt(value), input: Data(), times: lockNum, spaceDay: spaceDay, startDay: startDay)
        lockDes = "safe_lock.desc".localized(startDate.formatted(date: .abbreviated, time: .omitted), intervalMonth , "\(amount)", "\(lockNum)", "\(totalLockedAmount)")
        
        guard let availableBalance, totalLockedAmount <= availableBalance else {
            lockTips = "safe_zone.send.insufficientBalance".localized
            return
        }
        
        sendDisabled = false
        sendState = .ready(data: sendData)
    }
}

// address
extension SafeLineLockViewModel {
    private func syncAddressSecurityState() {
        switch addressResult {
        case .idle, .loading, .invalid:
            checkedResolvedAddress = nil
            addressSecurityState = .idle
            securityCheckViewModel.check(address: nil)
        case let .valid(success):
            securityCheckViewModel.check(address: success.address)
        }
    }

    private func syncFromCheckState(_ checkState: AddressSecurityCheckViewModel.State) {
        addressSecurityState = checkState

        switch checkState {
        case .idle, .checking:
            checkedResolvedAddress = nil
        case let .completed(address, detectedTypes):
            checkedResolvedAddress = ResolvedAddress(address: address.raw, issueTypes: detectedTypes)
        }
    }

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
            syncAddressSecurityState()
            syncSendData()
            return
        }

        addressResult = .valid(.init(address: address, uri: uri))
        addressCautionState = .none
        syncAddressSecurityState()
        syncSendData()
    }

    private func sync(_ error: Error, text: String) {
        addressResult = .invalid(.init(text: text, error: error))
        let caution = Caution(text: "watch_address.error.not_supported".localized, type: .error)
        addressCautionState = .caution(caution)
        syncAddressSecurityState()
        syncSendData()
    }
}

// amount
extension SafeLineLockViewModel {
    
    private func syncAmount() {
        guard enteringFiat else {
            return
        }

        guard let rate, let fiatAmount else {
            amount = nil
            return
        }

        amount = fiatAmount / rate
        syncAmountCautionState()
    }
    
    private func syncFiatAmount() {
        guard !enteringFiat else {
            return
        }

        guard let rate, let amount else {
            fiatAmount = nil
            return
        }

        fiatAmount = (amount * rate).rounded(decimal: 2)
    }
    
    func setAmountIn(percent: Int) {
        guard let availableBalance else {
            return
        }

        enteringFiat = false

        amount = (availableBalance * Decimal(percent) / 100).rounded(decimal: token.decimals)
    }
    
    func maxAmountIn() {
        setAmountIn(percent: 100)
        syncAmountCautionState()
    }
    
    func clearAmountIn() {
        enteringFiat = false
        amount = nil
    }
    
    private func syncAmountCautionState() {
        let caution = validateAmountIn()
        amountCautionState = caution != nil ? .caution(caution!) : .none
    }
    
    private func validateAmountIn() -> Caution? {
        var caution: Caution?
        guard let availableBalance else {
            return Caution(text: "safe_zone.balance_not_available".localized, type: .error)
        }
        if let amount, !amount.isZero {
            if amount < 0.01 {
                caution = Caution(text: "safe_zone.min_lock_amount_error".localized, type: .error)
                
            }else if amount > availableBalance {
                caution = Caution(text: "safe_zone.send.insufficientBalance".localized, type: .error)
                
            }else if amount == availableBalance {
                caution = Caution(text: "send.amount_warning.coin_needed_for_fee".localized(token.coin.code), type: .warning)
            }
        }else {
            caution = Caution(text: "safe_zone.min_lock_amount_error".localized, type: .error)
        }
        
        return caution
    }
}

// lockNum
extension SafeLineLockViewModel {
    
    func clearLockNum() {
        lockNumString = ""
    }
    
    private func syncLockNumCautionState() {
        let caution = validateLockNum()
        lockNumCautionState = caution != nil ? .caution(caution!) : .none
    }
    
    private func validateLockNum() -> Caution? {
        guard let lockNum, 1...360 ~= lockNum else {
            return Caution(text: "safe_lock.amount.error".localized("1-360"), type: .error)
        }
        return nil
    }
}

// intervalMonth
extension SafeLineLockViewModel {
    
    func clearIntervalMonth() {
        intervalMonthString = ""
    }
    
    private func syncIntervalMonthCautionState() {
        let caution = validateIntervalMonth()
        intervalMonthCautionState = caution != nil ? .caution(caution!) : .none
    }
    
    private func validateIntervalMonth() -> Caution? {
        guard let intervalMonth, 1...120 ~= intervalMonth else {
            return Caution(text: "safe_lock.amount.error".localized("1-120"), type: .error)
        }
        return nil
    }
}

extension SafeLineLockViewModel {
    enum FocusField: Int, Hashable {
        case address
        case amount
        case fiatAmount
        case lockNum
        case startDate
        case intervalMonth
    }
    
    enum SendState {
        case notReady
        case ready(data: TransactionData)
    }
}
