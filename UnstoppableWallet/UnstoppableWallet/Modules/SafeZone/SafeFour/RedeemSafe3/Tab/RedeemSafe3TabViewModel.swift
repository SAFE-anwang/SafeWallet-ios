
import Foundation
import RxSwift
import RxRelay
import RxCocoa

class RedeemSafe3TabViewModel {
    private let currentTabRelay: BehaviorRelay<RedeemSafe3Module.Tab>

    init() {
        currentTabRelay = BehaviorRelay<RedeemSafe3Module.Tab>(value: .other)
    }
}

extension RedeemSafe3TabViewModel {

    var currentTabDriver: Driver<RedeemSafe3Module.Tab> {
        currentTabRelay.asDriver()
    }

    var tabs: [RedeemSafe3Module.Tab] {
        RedeemSafe3Module.Tab.allCases
    }

    func onSelect(tab: RedeemSafe3Module.Tab) {
        currentTabRelay.accept(tab)
    }

}

