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

    init(service: MasterNodeRegisterService, decimalParser: AmountDecimalParser) {
        self.service = service
        self.decimalParser = decimalParser
    }
}

extension MasterNodeRegisterViewModel {
    func onChange(text: String?, type: MasterNodeInputType) {
        switch type {
        case .address:
            service.address = text
        case .ENODE:
            service.enode = text
        case .desc:
            service.desc = text
        }
    }
    
    func isValidInputParams() async throws -> Bool {
        
        let existCaution = service.syncCautionState()
        let isValidAddress = try await service.validateMasterNodeAddress()
        let isValidEnode = try await service.validateMasterNodeEnode()
        
        guard !existCaution && isValidAddress && isValidEnode else{
            return false
        }
        return true
    }
    
    func send(data: MasterNodeSendData) {
        state = .loading
        Task {
            do{
                if let _ = try await service.create(sendData: data) {
                    state = .completed
                }
            }catch {
                state = .failed(error: "safe_zone.safe4.craate.failed".localized)
            }
        }
    }
}

extension MasterNodeRegisterViewModel {
    
    var sendData: MasterNodeSendData? {
        service.getSendData()
    }
    
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
