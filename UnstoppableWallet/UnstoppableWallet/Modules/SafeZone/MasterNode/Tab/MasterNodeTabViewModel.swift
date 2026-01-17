import Foundation
import SwiftUI
import EvmKit
import Combine

class MasterNodeTabViewModel: ObservableObject {
    private let service: MasterNodeService
    @Published var currentTab: MasterNodeModule.Tab = .all

    var currentTabIndex: Binding<Int> {
        Binding<Int>(
            get: {
                MasterNodeModule.Tab.allCases.firstIndex(of: self.currentTab) ?? 0
            },
            set: { [self] index in
                currentTab = MasterNodeModule.Tab.allCases[index]
            }
        )
    }
    
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


