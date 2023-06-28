import Foundation
import RxSwift
import RxCocoa
import EvmKit
import MarketKit
import ComponentKit

class SendWsafeViewModel {
    private let service: SendWsafeService
    private let disposeBag = DisposeBag()

    private let proceedEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let amountCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let proceedRelay = PublishRelay<SendEvmData>()
    private let safeInfoManager: SafeInfoManager
    
    var isMatic: Bool = false
    var error: BinanceAdapter.AddressConversion?
    
    init(service: SendWsafeService) {
        self.service = service
        safeInfoManager = App.shared.safeInfoManager
        safeInfoManager.startNet()
        
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        subscribe(disposeBag, service.amountCautionObservable) { [weak self] in self?.sync(amountCaution: $0) }

        sync(state: service.state)
    }
    

    private func sync(state: SendWsafeService.State) {
        if case .ready = state {
            proceedEnabledRelay.accept(true)
        } else {
            proceedEnabledRelay.accept(false)
        }
    }

    private func sync(amountCaution: (error: Error?, warning: SendWsafeService.AmountWarning?)) {
        var caution: Caution? = nil

        if let error = amountCaution.error {
            let text = error.smartDescription.starts(with: "Read error:") ? "获取手续费异常，请稍等" : error.smartDescription
            caution = Caution(text: text, type: .error)
        } else if let warning = amountCaution.warning {
            switch warning {
            case .coinNeededForFee: caution = Caution(text: "send.amount_warning.coin_needed_for_fee".localized(service.sendToken.coin.code), type: .warning)
            }
        }

        amountCautionRelay.accept(caution)
    }

}

extension SendWsafeViewModel {

    var proceedEnableDriver: Driver<Bool> {
        proceedEnabledRelay.asDriver()
    }

    var amountCautionDriver: Driver<Caution?> {
        amountCautionRelay.asDriver()
    }

    var proceedSignal: Signal<SendEvmData> {
        proceedRelay.asSignal()
    }

    var token: Token {
        service.sendToken
    }

    func didTapProceed() {
        if let safeInfo = try? safeInfoManager.getSafeInfo() {
            guard (isMatic && safeInfo.matic?.safe2matic == true) || safeInfo.eth?.eth2safe == true else {
                HudHelper.instance.show(banner: .error(string: "safe_zone.Safe4_Disabled".localized))
                return
            }
            guard service.isSendMinAmount(safeInfo: safeInfo) else {
                let minamount = String(describing: safeInfo.minamount)
                HudHelper.instance.show(banner: .error(string: "safe_zone.Safe4_Min_Fee".localized(minamount)))
                return
            }
        }

        guard case .ready(let sendData) = service.state else {
            return
        }

        proceedRelay.accept(sendData)
    }
    
    /// - Parameters:
    ///   - wsafeWallet: 代币Wallet
    ///   - safeWallet: safe Wallet
    ///   - address: 跨链接收人 address
    func onEnterAddress(wsafeWallet: Wallet, safeWallet: Wallet, address: Address?) {
        if let depositAdapter = App.shared.adapterManager.depositAdapter(for: wsafeWallet) {
            let ethAddress = Address(raw: depositAdapter.receiveAddress, domain: nil)
            // 设置钱包的ETH地址为交易的接收地址
            service.setRecipientAddress(address: ethAddress, to: address)
        }
        // 验证跨链接收人地址是否Safe
        validateSafe(wallet: safeWallet, address: address)
    }
    
    func validateSafe(wallet: Wallet, address: Address?) {
        if let adapter = App.shared.adapterManager.adapter(for: wallet) {
            error = nil
            switch adapter {
            case let adapter as ISendSafeCoinAdapter:
                if let addressRaw = address?.raw {
                    do {
                        try adapter.validateSafe(address: addressRaw)
                    }catch {
                        print("invalidAddress")
                        // throw BinanceAdapter.AddressConversion.invalidAddress
                    }
                    
                }
            default: return 
            }
            
        }
     }

}
