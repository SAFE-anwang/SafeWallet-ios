import Foundation
import RxSwift
import RxRelay
import RxCocoa
import EvmKit

class ProposalTabViewModel {
    private let currentTabRelay: BehaviorRelay<ProposalModule.Tab>
    private let evmKit: EvmKit.Kit
    init(evmKit: EvmKit.Kit) {
        self.evmKit = evmKit
        currentTabRelay = BehaviorRelay<ProposalModule.Tab>(value: .all)
    }

}

extension ProposalTabViewModel {

    var currentTabDriver: Driver<ProposalModule.Tab> {
        currentTabRelay.asDriver()
    }

    var tabs: [ProposalModule.Tab] {
        ProposalModule.Tab.allCases
    }

    func onSelect(tab: ProposalModule.Tab) {
        currentTabRelay.accept(tab)
    }
    
    var isEnabledAdd: Bool {
        (evmKit.lastBlockHeight ?? 0) > 86400
    }

}
