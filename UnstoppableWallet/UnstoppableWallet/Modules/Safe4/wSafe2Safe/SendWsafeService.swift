import Foundation
import MarketKit
import RxSwift
import RxRelay
import EvmKit
import BigInt
import HsExtensions
import HsToolKit

class SendWsafeService {
    let sendToken: Token
    private let disposeBag = DisposeBag()
    private let adapter: ISendEthereumAdapter
    private let addressService: AddressService

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notReady {
        didSet {
            stateRelay.accept(state)
        }
    }

    private var evmAmount: BigUInt?
    private var addressData: AddressData?
    private var toSafeAddress: Address? // 跨链接收人Address

    private let amountCautionRelay = PublishRelay<(error: Error?, warning: AmountWarning?)>()
    private var amountCaution: (error: Error?, warning: AmountWarning?) = (error: nil, warning: nil) {
        didSet {
            amountCautionRelay.accept(amountCaution)
        }
    }

    init(token: Token, adapter: ISendEthereumAdapter, addressService: AddressService) {
        sendToken = token
        self.adapter = adapter
        self.addressService = addressService

        subscribe(disposeBag, addressService.stateObservable) { [weak self] in self?.sync(addressState: $0) }
    }

    private func sync(addressState: AddressService.State) {
        switch addressState {
        case .success(let address):
            toSafeAddress = address
        default: toSafeAddress = nil
        }
        syncState()
    }

    private func syncState() {
        if amountCaution.error == nil, case .success = addressService.state, let evmAmount = evmAmount, let addressData = addressData, let safeAddr = toSafeAddress?.raw {
            let wsafeKit = WSafeKit(chain: adapter.evmKitWrapper.evmKit.chain)
            let transactionData = wsafeKit.transactionData(amount: evmAmount, to: safeAddr)
            let sendInfo = SendEvmData.SendInfo(domain: addressData.domain)
            let sendData = SendEvmData(transactionData: transactionData, additionalInfo: .send(info: sendInfo), warnings: [])
            state = .ready(sendData: sendData)
        } else {
            state = .notReady
        }
    }

    private func validEvmAmount(amount: Decimal) throws -> BigUInt {
        guard let evmAmount = BigUInt(amount.hs.roundedString(decimal: sendToken.decimals)) else {
            throw AmountError.invalidDecimal
        }

        guard amount <= adapter.balanceData.available else {
            throw AmountError.insufficientBalance
        }

        return evmAmount
    }

}

extension SendWsafeService {

    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var amountCautionObservable: Observable<(error: Error?, warning: AmountWarning?)> {
        amountCautionRelay.asObservable()
    }

}

extension SendWsafeService: IAvailableBalanceService {

    var availableBalance: DataStatus<Decimal> {
        .completed(adapter.balanceData.available)
    }

    var availableBalanceObservable: Observable<DataStatus<Decimal>> {
        Observable.just(availableBalance)
    }

}
extension SendWsafeService {
    
    func setRecipientAddress(address: Address?, to: Address?) {
        if let address = address {
            do {
                addressData = AddressData(evmAddress: try EvmKit.Address(hex: address.raw), domain: address.domain)
            } catch {
                addressData = nil
            }
        }
        toSafeAddress = to
        syncState()
    }
    
    func isSendMinAmount(safeInfo: SafeChainInfo) -> Bool {
        
        let minSafe = BigUInt(Decimal(floatLiteral: safeInfo.minamount).hs.roundedString(decimal: 18)) ?? 0
        let safeAmount = evmAmount ?? 0
        return  safeAmount >= minSafe
    }
}

extension SendWsafeService: IAmountInputService {

    var amount: Decimal {
        0
    }

    var token: Token? {
        sendToken
    }

    var balance: Decimal? {
        adapter.balanceData.available
    }

    var amountObservable: Observable<Decimal> {
        .empty()
    }

    var tokenObservable: Observable<Token?> {
        .empty()
    }

    var balanceObservable: Observable<Decimal?> {
        .just(adapter.balanceData.available)
    }

    func onChange(amount: Decimal) {
        if amount > 0 {
            do {
                evmAmount = try validEvmAmount(amount: amount)

                var amountWarning: AmountWarning? = nil
                if amount.isEqual(to: adapter.balanceData.available) {
                    switch sendToken.blockchainType {
                    case .ethereum, .binanceSmartChain, .polygon: amountWarning = AmountWarning.coinNeededForFee
                    default: ()
                    }
                }

                amountCaution = (error: nil, warning: amountWarning)
            } catch {
                evmAmount = nil
                amountCaution = (error: error, warning: nil)
            }
        } else {
            evmAmount = nil
            amountCaution = (error: nil, warning: nil)
        }

        syncState()
    }

}

extension SendWsafeService {

    enum State {
        case ready(sendData: SendEvmData)
        case notReady
    }

    enum AmountError: Error {
        case invalidDecimal
        case insufficientBalance
    }

    enum AmountWarning {
        case coinNeededForFee
    }

    private struct AddressData {
        let evmAddress: EvmKit.Address
        let domain: String?
    }

}
