import Foundation
import RxSwift
import RxRelay
import RxCocoa

class SuperNodeTabViewModel {
    private let service: SuperNodeService
    private let currentTabRelay: BehaviorRelay<SuperNodeModule.Tab>

    init(service: SuperNodeService) {
        self.service = service
        currentTabRelay = BehaviorRelay<SuperNodeModule.Tab>(value: .all)
    }
}

extension SuperNodeTabViewModel {
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var currentTabDriver: Driver<SuperNodeModule.Tab> {
        currentTabRelay.asDriver()
    }

    var tabs: [SuperNodeModule.Tab] {
        SuperNodeModule.Tab.allCases
    }

    func onSelect(tab: SuperNodeModule.Tab) {
        currentTabRelay.accept(tab)
    }

}
