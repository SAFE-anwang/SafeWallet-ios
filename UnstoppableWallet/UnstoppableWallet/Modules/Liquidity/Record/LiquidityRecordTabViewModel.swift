import Foundation
import RxSwift
import RxRelay
import RxCocoa

class LiquidityRecordTabViewModel {
    private let disposeBag = DisposeBag()
    private let currentTabRelay: BehaviorRelay<LiquidityRecordModule.Tab>

    init() {
        currentTabRelay = BehaviorRelay<LiquidityRecordModule.Tab>(value: .bsc)
    }

}

extension LiquidityRecordTabViewModel {

    var currentTabDriver: Driver<LiquidityRecordModule.Tab> {
        currentTabRelay.asDriver()
    }

    var tabs: [LiquidityRecordModule.Tab] {
        LiquidityRecordModule.Tab.allCases
    }

    func onSelect(tab: LiquidityRecordModule.Tab) {
        currentTabRelay.accept(tab)
    }

}
