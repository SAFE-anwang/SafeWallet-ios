import UIKit
import EvmKit
import ComponentKit
import BigInt

struct MasterNodeModule {
    
    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }
        let service = MasterNodeService(evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeTabViewModel(service: service)
        let viewController = MasterNodeTabViewController(viewModel: viewModel, evmKit: evmKitWrapper.evmKit)
        return viewController
    }
    
    static func subViewController(type: MasterNodeType, evmKit: EvmKit.Kit) -> MasterNodeViewController {
        let service = MasterNodeService(evmKit: evmKit)
        let viewModel = MasterNodeViewModel(service: service, type: type)
        return MasterNodeViewController(viewModel: viewModel)
    }
        
    enum Tab: Int, CaseIterable {
        case all
        case mine
        
        var title: String {
            switch self {
            case .all: return "主节点列表".localized
            case .mine: return "我的主节点".localized
            }
        }
    }
    
    enum MasterNodeType {
        case All
        case Mine
    }
}

enum MasterNodeInputType {
    case address
    case ENODE
    case desc
    
    var title: String {
        switch self {
        case .address: return "主节点钱包地址".localized
        case .ENODE: return "ENODE".localized
        case .desc: return "简介".localized
        }
    }
    
    var placeholder: String {
        switch self {
        case .address: return "输入主节点钱包地址".localized
        case .ENODE: return "输入主节点ENODE".localized
        case .desc: return "输入简介信息".localized
        }
    }
    
    var keyboardType: UIKeyboardType {
        .default
    }
}
