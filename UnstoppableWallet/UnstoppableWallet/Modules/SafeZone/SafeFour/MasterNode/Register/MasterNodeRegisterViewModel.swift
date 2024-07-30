import Foundation
import BigInt
import RxSwift
import RxCocoa

class MasterNodeRegisterViewModel {
    private let service: MasterNodeRegisterService
    private let decimalParser: AmountDecimalParser
    private var stateRelay = PublishRelay<MasterNodeRegisterViewModel.State>()
    
    private(set) var state: MasterNodeRegisterViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private var isEnabledSend = true

    init(service: MasterNodeRegisterService, decimalParser: AmountDecimalParser) {
        self.service = service
        self.decimalParser = decimalParser
    }
}

extension MasterNodeRegisterViewModel {
    func onChange(text: String?, type: MasterNodeRegisterCell.InputType) {
        switch type {
        case .address:
            service.address = text
        case .ENODE:
            service.enode = text
        case .desc:
            service.desc = text
        }
    }
    
    func send() {
        let existCaution = service.syncCautionState()
        state = .loading
        Task {
            do{
                let isValidAddress = try await service.validateSuperNodeAddress()
                let isValidEnode = try await service.validateSuperNodeEnode()
                
                guard !existCaution && isValidAddress && isValidEnode else{ return }
                guard isEnabledSend else { return }
                isEnabledSend = false
                if let _ = try await service.create() {
                    state = .completed
                }
                isEnabledSend = true
            }catch {
                isEnabledSend = true
                state = .failed(error: "创建失败")
            }
        }
    }
}

extension MasterNodeRegisterViewModel {
    
    var stateDriver: Observable<MasterNodeRegisterViewModel.State> {
        stateRelay.asObservable()
    }
    
    var balance: String {
        "\(service.balance ?? 0.00) SAFE"
    }
    var address: String? {
        service.address
    }
    
    var masterNodeIncentive: MasterNodeRegisterService.MasterNodeIncentive {
        service.masterNodeIncentive
    }
    var createModeDriver: Driver<MasterNodeRegisterService.CreateMode> {
        service.createModeDriver
    }
    var createMode: MasterNodeRegisterService.CreateMode {
        service.createMode
    }
    var balanceDriver: Driver<Decimal?> {
        service.balanceDriver
    }
    var balanceCautionDriver: Driver<Caution?> {
        service.balanceCautionDriver
    }
    var addressDriver: Driver<String?> {
        service.addressDriver
    }
    var addressCautionDriver: Driver<Caution?> {
        service.addressCautionDriver
    }
    var enodeCautionDriver: Driver<Caution?> {
        service.enodeCautionDriver
    }
    var descCautionDriver: Driver<Caution?> {
        service.descCautionDriver
    }
    
    func update(mode: MasterNodeRegisterService.CreateMode) {
        service.createMode = mode
    }
    
    func update(sliderValue: Float) {
        service.masterNodeIncentive.updateSlider(value: sliderValue)
    }
    
    enum State {
        case loading
        case completed
        case failed(error: String)
    }
    
}
