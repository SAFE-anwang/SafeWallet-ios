import Foundation
import RxSwift
import RxRelay
import RxCocoa

class MasterNodeTabViewModel {
    private let service: MasterNodeService

    private let currentTabRelay: BehaviorRelay<MasterNodeModule.Tab>

    init(service: MasterNodeService) {
        self.service = service
        currentTabRelay = BehaviorRelay<MasterNodeModule.Tab>(value: .all)
    }
}

extension MasterNodeTabViewModel {
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var currentTabDriver: Driver<MasterNodeModule.Tab> {
        currentTabRelay.asDriver()
    }

    var tabs: [MasterNodeModule.Tab] {
        MasterNodeModule.Tab.allCases
    }

    func onSelect(tab: MasterNodeModule.Tab) {
        currentTabRelay.accept(tab)
    }

}

