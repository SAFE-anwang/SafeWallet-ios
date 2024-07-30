import Foundation
import RxSwift
import RxRelay
import RxCocoa

class ProposalTabViewModel {
    private let currentTabRelay: BehaviorRelay<ProposalModule.Tab>

    init() {
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

}
