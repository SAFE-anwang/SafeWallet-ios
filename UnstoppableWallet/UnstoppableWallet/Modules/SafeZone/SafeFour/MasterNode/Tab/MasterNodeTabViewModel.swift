import Foundation
import RxSwift
import RxRelay
import RxCocoa
import EvmKit
import Combine

class MasterNodeTabViewModel: ObservableObject {
    private let service: MasterNodeService
    private let keyTab = "MasterNode-tab"
    @Published var currentTab: MasterNodeModule.Tab = .all

    init(service: MasterNodeService) {
        self.service = service
    }
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var evmKit: EvmKit.Kit{
        service.evmKit
    }
}


