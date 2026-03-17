import Foundation
import Combine

class LiquidityRecordTabViewModel: ObservableObject {
    @Published var currentTab: LiquidityRecordModule.Tab = .safe

//    private let disposeBag = DisposeBag()
//    private let currentTabRelay: BehaviorRelay<LiquidityRecordModule.Tab>
//
//    init() {
//        currentTabRelay = BehaviorRelay<LiquidityRecordModule.Tab>(value: .safe)
//    }

}
//
//extension LiquidityRecordTabViewModel {
//
//    var currentTabDriver: Driver<LiquidityRecordModule.Tab> {
//        currentTabRelay.asDriver()
//    }
//
//    var tabs: [LiquidityRecordModule.Tab] {
//        LiquidityRecordModule.Tab.allCases
//    }
//
//    func onSelect(tab: LiquidityRecordModule.Tab) {
//        currentTabRelay.accept(tab)
//    }
//
//}
