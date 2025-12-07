import Foundation
import UIKit
import EvmKit
import MarketKit

class DeployModule {

    static func viewModel() -> DeployViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SRC20Service(privateKey: privateKey)
        let viewModel = DeployViewModel(service: service, evmKitWrapper: evmKitWrapper)
        return viewModel
    }
    
}

enum DeployType: Int, CaseIterable, Hashable, Identifiable {
    case SRC20 = 0
    case SRC20Mintable = 1
    case SRC20Burnable = 2

    var title: String {
        switch self {
        case .SRC20: "SRC20_Deploy_Type_Normal".localized
        case .SRC20Mintable: "SRC20_Deploy_Type_Mintable".localized
        case .SRC20Burnable: "SRC20_Deploy_Type_Burnable".localized
        }
    }
    
    var des: String {
        switch self {
        case .SRC20: "SRC20_Deploy_Type_Normal_Desc".localized
        case .SRC20Mintable: "SRC20_Deploy_Type_Mintable_Desc".localized
        case .SRC20Burnable: "SRC20_Deploy_Type_Burnable_Desc".localized
        }
    }
    
    var id: Self {
        self
    }
}
