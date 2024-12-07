import Foundation
import BigInt
import RxSwift
import RxCocoa

class SuperNodeRegisterViewModel {
    private let service: SuperNodeRegisterService
    private let decimalParser: AmountDecimalParser
    private var stateRelay = PublishRelay<SuperNodeRegisterViewModel.State>()
    
    private(set) var state: SuperNodeRegisterViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    init(service: SuperNodeRegisterService, decimalParser: AmountDecimalParser) {
        self.service = service
        self.decimalParser = decimalParser
    }
}

extension SuperNodeRegisterViewModel {
    func onChange(text: String?, type: SuperNodeInputType) {
        switch type {
        case .address:
            service.address = text
        case .ENODE:
            service.enode = text
        case .desc:
            service.desc = text
        case .name:
            service.name = text
        }
    }
    
    func isValidInputParams() async throws -> Bool {
        let existCaution = service.syncCautionState()
        let isValidName = try await service.validateSuperNodeName()
        let isValidAddress = try await service.validateSuperNodeAddress()
        let isValidEnode = try await service.validateSuperNodeEnode()
        
        guard !existCaution && isValidName && isValidAddress && isValidEnode else{
            return false
        }
        return true
    }
    
    func send(data: SuperNodeSendData) {
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

extension SuperNodeRegisterViewModel {
    
    var sendData: SuperNodeSendData? {
        service.getSendData()
    }
    
    var stateDriver: Observable<SuperNodeRegisterViewModel.State> {
        stateRelay.asObservable()
    }
    
    var balance: String {
        "\(service.balance ?? 0.00) SAFE"
    }
    var address: String? {
        service.address
    }
    
    var superNodeIncentive: SuperNodeRegisterService.SuperNodeIncentive {
        service.superNodeIncentive
    }
    var createModeDriver: Driver<SuperNodeRegisterService.CreateMode> {
        service.createModeDriver
    }
    var createMode: SuperNodeRegisterService.CreateMode {
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
    var nameCautionDriver: Driver<Caution?> {
        service.nameCautionDriver
    }
    var enodeCautionDriver: Driver<Caution?> {
        service.enodeCautionDriver
    }
    var descCautionDriver: Driver<Caution?> {
        service.descCautionDriver
    }
    
    func update(mode: SuperNodeRegisterService.CreateMode) {
        service.createMode = mode
    }
    
    func update(leftSliderValue: Float) {
        service.superNodeIncentive.updateLeftSlider(value: leftSliderValue)
    }
    
    func update(rightSliderValue: Float) {
        service.superNodeIncentive.updateRightSlider(value: rightSliderValue)
    }
    
    enum State {
        case loading
        case completed
        case failed(error: String)
    }
    
}

