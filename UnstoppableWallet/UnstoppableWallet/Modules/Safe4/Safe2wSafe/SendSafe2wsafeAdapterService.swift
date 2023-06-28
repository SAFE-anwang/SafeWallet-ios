import Foundation
import RxSwift
import RxCocoa
import RxRelay
import HsToolKit
import Hodler
import EvmKit

class SendSafe2wsafeAdapterService {
    private let disposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "io.horizontalsystems.unstoppable.send.wsafe_adapter_service", qos: .userInitiated)

    private let feeRateService: FeeRateService
    private let amountInputService: IAmountInputService
    private let addressService: AddressService
    private let timeLockService: TimeLockService?
    private let btcBlockchainManager: BtcBlockchainManager
    private let adapter: ISendSafeCoinAdapter
    private let ethAdapter: ISendEthereumAdapter
    
    private var contractAddressHex: String? = nil
    private var toAddressHex: String? // 跨链接收人Address
//    private var toAddressData: AddressData? // 跨链接收人AddressData
    
    let inputOutputOrderService: InputOutputOrderService

    // Outputs
    let feeStateRelay = BehaviorRelay<DataStatus<Decimal>>(value: .loading)
    var feeState: DataStatus<Decimal> = .loading {
        didSet {
            if !feeState.equalTo(oldValue) {
                feeStateRelay.accept(feeState)
            }
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

    init(feeRateService: FeeRateService, amountInputService: IAmountInputService, addressService: AddressService,
         inputOutputOrderService: InputOutputOrderService, timeLockService: TimeLockService?, btcBlockchainManager: BtcBlockchainManager, adapter: ISendSafeCoinAdapter, ethAdapter: ISendEthereumAdapter, contractAddress: Address?) {
        self.feeRateService = feeRateService
        self.amountInputService = amountInputService
        self.addressService = addressService
        self.timeLockService = timeLockService
        self.inputOutputOrderService = inputOutputOrderService
        self.btcBlockchainManager = btcBlockchainManager
        self.adapter = adapter
        self.ethAdapter = ethAdapter
        
        self.toAddressHex = ethAdapter.evmKitWrapper.evmKit.address.hex
        
        if let address = contractAddress {
            contractAddressHex = address.raw
            minimumSendAmount = adapter.minimumSendAmountSafe(address: address.raw)
        }
        
        App.shared.safeInfoManager.startNet()
        
        sync(feeRate: .completed(10))
        
        subscribe(disposeBag, amountInputService.amountObservable) { [weak self] _ in
            self?.sync(updatedFrom: .amount)
        }
        subscribe(disposeBag, addressService.stateObservable) { [weak self] _ in
            self?.sync(updatedFrom: .address)
        }

        if let timeLockService = timeLockService {
            subscribe(disposeBag, timeLockService.pluginDataObservable) { [weak self] _ in
                self?.sync(updatedFrom: .pluginData)
            }
        }

        subscribe(disposeBag, feeRateService.statusObservable) { [weak self] in
            self?.sync(feeRate: $0)
        }
        
    }

    private func sync(feeRate: DataStatus<Int>? = nil, updatedFrom: UpdatedField = .feeRate) {
        let feeRate = feeRate ?? feeRateService.status
        let amount = amountInputService.amount

        switch feeRate {
        case .loading:
            guard !amount.isZero else {      // force update fee for bitcoin, when clear amount to zero value
                feeState = .completed(0)
                return
            }

            feeState = .loading
        case .failed(let error):
            feeState = .failed(error)
        case .completed(let feeRate):
            // addressService.state.address?.raw
            update(feeRate: feeRate, amount: amount, address: contractAddressHex, pluginData: pluginData, updatedFrom: updatedFrom)
        }
    }

    private func update(feeRate: Int, amount: Decimal, address: String?, pluginData: [UInt8: IBitcoinPluginData], updatedFrom: UpdatedField) {
        queue.async { [weak self] in
            if let fee = self?.adapter.convertFeeSafe(amount: amount, address: address), let newFee = self?.newFee(fee) {
                self?.feeState = .completed(newFee)
            }
            if updatedFrom != .amount,
               let availableBalance = self?.adapter.availableBalanceSafe(address: address){
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
    
    private func getReverseHex(addressHex: String) -> String {
        var wsafeAddress = ""
        let safeRemarkPrex = "736166650100c9dcee22bb18bd289bca86e2c8bbb6487089adc9a13d875e538dd35c70a6bea42c0100000a020100122e"
        switch ethAdapter.evmKitWrapper.blockchainType {
        case .binanceSmartChain:
            wsafeAddress = "bsc:" + addressHex
        case .ethereum:
            wsafeAddress = "eth:" + addressHex
        case .polygon:
            wsafeAddress = "matic:" + addressHex
        default: break
        }
        return safeRemarkPrex + wsafeAddress.hs.data.toHexString()
    }
    
    func newFee(_ fee: Decimal) -> Decimal {
        var newFee = fee
        do {
            let safeInfo = try App.shared.safeInfoManager.getSafeInfo()
            switch ethAdapter.evmKitWrapper.blockchainType {
            case .binanceSmartChain:
                newFee += Decimal(safeInfo.bsc?.safe_fee ?? 0)
            case .ethereum:
                newFee += Decimal(safeInfo.eth?.safe_fee ?? 0)
            case .polygon:
                newFee += Decimal(safeInfo.matic?.safe_fee ?? 0)
            default: break
            }
            return newFee
            
        }catch {}
        
        return newFee
    }

}

extension SendSafe2wsafeAdapterService: ISendXFeeValueService, IAvailableBalanceService, ISendXSendAmountBoundsService {

    var feeStateObservable: Observable<DataStatus<Decimal>> {
        feeStateRelay.asObservable()
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

extension SendSafe2wsafeAdapterService: ISendService {

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
        guard let contractAddress = contractAddressHex else {
            return Single.error(SendTransactionError.invalidAddress)
        }
        
        let reverseHex = getReverseHex(addressHex: address.raw)
        return adapter.sendSingle(amount: amountInputService.amount, address: contractAddress, sortMode: .shuffle, logger: logger, lockedTimeInterval: nil, reverseHex: reverseHex)
    }

}

extension SendSafe2wsafeAdapterService {

    private enum UpdatedField: String {
        case amount, address, pluginData, feeRate
    }

}


