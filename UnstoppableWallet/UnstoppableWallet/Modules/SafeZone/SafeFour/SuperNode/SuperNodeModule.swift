import UIKit
import BigInt
import EvmKit
import ComponentKit

struct SuperNodeModule {
    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SuperNodeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeTabViewModel(service: service)
        let viewController = SuperNodeTabViewController(viewModel: viewModel, evmKit: evmKitWrapper.evmKit, privateKey: privateKey)
        return viewController
    }
    
    static func subViewController(type: SuperNodeType, evmKit: EvmKit.Kit, privateKey: Data) -> SuperNodeViewController {
        let service = SuperNodeService(privateKey: privateKey, evmKit: evmKit)
        let viewModel = SuperNodeViewModel(service: service, type: type)
        return SuperNodeViewController(viewModel: viewModel)
    }
        
    enum Tab: Int, CaseIterable {
        case all
        case mine
        
        var title: String {
            switch self {
            case .all: return "safe_zone.safe4.node.super.list".localized
            case .mine: return "safe_zone.safe4.node.super.mine".localized
            }
        }
    }
    
    enum SuperNodeType {
        case All
        case Mine
    }
}


