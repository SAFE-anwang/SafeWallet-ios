import Foundation
import EvmKit
import Combine

class ProposalTabViewModel: ObservableObject {
    @Published var currentTab: ProposalModule.Tab = .all
    let evmKit: EvmKit.Kit
    let privateKey: Data
    
    init(evmKit: EvmKit.Kit, privateKey: Data) {
        self.evmKit = evmKit
        self.privateKey = privateKey
    }
}

extension ProposalTabViewModel {
    
    var tabs: [ProposalModule.Tab] {
        ProposalModule.Tab.allCases
    }

    var isEnabledAdd: Bool {
        (evmKit.lastBlockHeight ?? 0) > 86400
    }
}

