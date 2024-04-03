import Combine
import BitcoinCore
import Foundation
import RxSwift
import RxCocoa
import RxRelay
import HsToolKit
import Hodler
import EvmKit

class SendSafeCoinAdapterService {
    private let disposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "anwang.safewallet.send.safe_adapter_service", qos: .userInitiated)

    private let feeRateService: FeeRateService
    private let amountInputService: IAmountInputService
    private let addressService: AddressService
    private let memoService: SendMemoInputService
    private let timeLockService: TimeLockService?
    private let btcBlockchainManager: BtcBlockchainManager
    private let adapter: ISendSafeCoinAdapter
    let inputOutputOrderService: InputOutputOrderService
    let rbfService: RbfService
    
    let customOutputsUpdatedSubject = PassthroughSubject<Void, Never>()
    var customOutputs: [UnspentOutputInfo]? {
        didSet {
            if customOutputs != oldValue {
                sync()
                customOutputsUpdatedSubject.send()
            }
        }
    }

    // Outputs
    let feeStateRelay = BehaviorRelay<DataStatus<Decimal>>(value: .loading)
    var feeState: DataStatus<Decimal> = .loading {
        didSet {
            if !feeState.equalTo(oldValue) {
                feeStateRelay.accept(feeState)
            }
        }
    }
    
    let sendInfoRelay = BehaviorRelay<DataStatus<SendInfo>>(value: .loading)
    var sendInfoState: DataStatus<SendInfo> = .loading {
        didSet {
            feeState = sendInfoState.map(\.fee)
            sendInfoRelay.accept(sendInfoState)
        }
    }

    let availableBalanceRelay = BehaviorRelay<DataStatus<Decimal>>(value: .loading)
    var availableBalance: DataStatus<Decimal> = .loading {
        didSet {
            if !availableBalance.equalTo(oldValue) {
                availableBalanceRelay.accept(availableBalance)
            }
        }
    }

    let minimumSendAmountRelay = BehaviorRelay<Decimal>(value: 0)
    var minimumSendAmount: Decimal = 0 {
        didSet {
            if minimumSendAmount != oldValue {
                minimumSendAmountRelay.accept(minimumSendAmount)
            }
        }
    }

    let maximumSendAmountRelay = BehaviorRelay<Decimal?>(value: nil)
    var maximumSendAmount: Decimal? = nil {
        didSet {
            if maximumSendAmount != oldValue {
                maximumSendAmountRelay.accept(maximumSendAmount)
            }
        }
    }

    init(feeRateService: FeeRateService, amountInputService: IAmountInputService, addressService: AddressService, memoService: SendMemoInputService,
         inputOutputOrderService: InputOutputOrderService, rbfService: RbfService, timeLockService: TimeLockService?, btcBlockchainManager: BtcBlockchainManager, adapter: ISendSafeCoinAdapter) {
        self.feeRateService = feeRateService
        self.amountInputService = amountInputService
        self.addressService = addressService
        self.timeLockService = timeLockService
        self.memoService = memoService
        self.inputOutputOrderService = inputOutputOrderService
        self.btcBlockchainManager = btcBlockchainManager
        self.rbfService = rbfService
        self.adapter = adapter
        
        sync(feeRate: .completed(10))
        
        subscribe(disposeBag, amountInputService.amountObservable) { [weak self] _ in
            self?.sync(updatedFrom: .amount)
        }
        subscribe(disposeBag, addressService.stateObservable) { [weak self] _ in
            self?.sync(updatedFrom: .address)
        }
        
        subscribe(disposeBag, memoService.memoObservable) { [weak self] _ in
            self?.sync(updatedFrom: .memo)
        }
        
        if let timeLockService {
            subscribe(disposeBag, timeLockService.pluginDataObservable) { [weak self] _ in
                self?.sync(updatedFrom: .pluginData)
            }
        }

        subscribe(disposeBag, feeRateService.statusObservable) { [weak self] in
            self?.sync(feeRate: $0)
        }

        minimumSendAmount = adapter.minimumSendAmountSafe(address: addressService.state.address?.raw)
     //   maximumSendAmount = adapter.maximumSendAmount(pluginData: pluginData)
    }

    private func sync(feeRate: DataStatus<Int>? = nil, updatedFrom: UpdatedField = .feeRate) {
        let feeRateStatus = feeRate ?? feeRateService.status
        let amount = amountInputService.amount
        var feeRate = 0

        switch feeRateStatus {
        case .loading:
            guard !amount.isZero else { // force update fee for bitcoin, when clear amount to zero value
                sendInfoState = .completed(SendInfo.empty)
                return
            }

            sendInfoState = .loading
        case let .failed(error):
            sendInfoState = .failed(error)
        case let .completed(_feeRate):
            feeRate = _feeRate
        }

        update(feeRate: feeRate, amount: amount, address: addressService.state.address?.raw, pluginData: pluginData, updatedFrom: updatedFrom)
    }

    private func update(feeRate: Int, amount: Decimal, address: String?, pluginData: [UInt8: IBitcoinPluginData], updatedFrom: UpdatedField) {
        
        let memo = memoService.memo
        queue.async { [weak self] in
            do {
                if let sendInfo = try self?.adapter
                    .sendInfoSafe(amount: amount, feeRate: feeRate, address: address, memo: memo, unspentOutputs: self?.customOutputs, pluginData: pluginData)
                {
                    self?.sendInfoState = .completed(sendInfo)
                }
            } catch {
                self?.sendInfoState = .failed(error)
            }
            if updatedFrom != .amount,
               let availableBalance = self?.adapter.availableBalanceSafe(feeRate: feeRate, address: address, memo: memo, unspentOutputs: self?.customOutputs, pluginData: pluginData){
                self?.availableBalance = .completed(availableBalance)
            }
//            if updatedFrom == .pluginData {
//                self?.maximumSendAmount = self?.adapter.maximumSendAmount(pluginData: pluginData)
//            }
            if updatedFrom == .address {
                self?.minimumSendAmount = self?.adapter.minimumSendAmountSafe(address: address) ?? 0
            }
        }
    }

    private var pluginData: [UInt8: IBitcoinPluginData] {
        timeLockService?.pluginData ?? [:]
    }

}

extension SendSafeCoinAdapterService: ISendInfoValueService, ISendXFeeValueService, IAvailableBalanceService, ISendXSendAmountBoundsService {
    var unspentOutputs: [UnspentOutputInfo] {
        adapter.unspentOutputs
    }

    var customOutputsUpdatedPublisher: AnyPublisher<Void, Never> {
        customOutputsUpdatedSubject.eraseToAnyPublisher()
    }
    
    var feeStateObservable: Observable<DataStatus<Decimal>> {
        feeStateRelay.asObservable()
    }
    
    var sendInfoStateObservable: Observable<DataStatus<SendInfo>> {
        sendInfoRelay.asObservable()
    }

    var availableBalanceObservable: Observable<DataStatus<Decimal>> {
        availableBalanceRelay.asObservable()
    }

    var minimumSendAmountObservable: Observable<Decimal> {
        minimumSendAmountRelay.asObservable()
    }

    var maximumSendAmountObservable: Observable<Decimal?> {
        maximumSendAmountRelay.asObservable()
    }

    func validate(address: String) throws {
        try adapter.validateSafe(address: address)
    }

}

extension SendSafeCoinAdapterService: ISendService {

    func sendSingle(logger: Logger) -> Single<Void> {
        let address: Address
        switch addressService.state {
        case .success(let sendAddress): address = sendAddress
        case .fetchError(let error): return Single.error(error)
        default: return Single.error(AppError.addressInvalid)
        }

        guard case let .completed(feeRate) = feeRateService.status else {
            return Single.error(SendTransactionError.noFee)
        }

        guard !amountInputService.amount.isZero else {
            return Single.error(SendTransactionError.wrongAmount)
        }
        
        let rbfEnabled = btcBlockchainManager.transactionRbfEnabled(blockchainType: adapter.blockchainType)
        let data = pluginData[HodlerPlugin.id] as? HodlerData
        return adapter.sendSingle(
            amount: amountInputService.amount,
            address: address.raw,
            memo: memoService.memo,
            feeRate: feeRate,
            unspentOutputs: customOutputs,
            pluginData: pluginData,
            sortMode: .shuffle,
            rbfEnabled: rbfEnabled,
            logger: logger,
            lockedTimeInterval: data?.lockTimeInterval,
            reverseHex: nil
        )
    }

}

extension SendSafeCoinAdapterService {

    private enum UpdatedField: String {
        case amount, address, memo, pluginData, feeRate
    }

}

