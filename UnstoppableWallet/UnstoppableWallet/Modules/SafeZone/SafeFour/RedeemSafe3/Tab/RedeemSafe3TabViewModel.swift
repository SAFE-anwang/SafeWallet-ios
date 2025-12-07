
import Foundation
import Combine

class RedeemSafe3TabViewModel: ObservableObject {
    @Published var currentTab: RedeemSafe3Module.Tab = .other
    let account: Account
    let safe4EvmKitWrapper: EvmKitWrapper
    
    init(account: Account, safe4EvmKitWrapper: EvmKitWrapper) {
//        self.currentTab = currentTab
        self.account = account
        self.safe4EvmKitWrapper = safe4EvmKitWrapper
    }
    var tabs: [RedeemSafe3Module.Tab] {
        RedeemSafe3Module.Tab.allCases
    }
}

