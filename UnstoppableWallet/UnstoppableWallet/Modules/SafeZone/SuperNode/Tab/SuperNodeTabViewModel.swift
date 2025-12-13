import Foundation
import Combine
import EvmKit

class SuperNodeTabViewModel: ObservableObject {
    let service: SuperNodeService
    @Published var currentTab: SuperNodeModule.Tab = .all

    init(service: SuperNodeService) {
        self.service = service
    }
    
    var evmKit: EvmKit.Kit{
        service.evmKit
    }
    
    var privateKey: Data {
        service.privateKey
    }
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
}
