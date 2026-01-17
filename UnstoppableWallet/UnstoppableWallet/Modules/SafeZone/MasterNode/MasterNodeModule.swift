import UIKit
import EvmKit
import BigInt
import SwiftUI

struct MasterNodeModule {
    
    static func tabViewModel() -> MasterNodeTabViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        let service = MasterNodeService(evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeTabViewModel(service: service)
        return viewModel
    }
    
    static func viewModel(type: MasterNodeType, evmKit: EvmKit.Kit) -> MasterNodeViewModel {
        let service = MasterNodeService(evmKit: evmKit)
        let viewModel = MasterNodeViewModel(service: service, type: type)
        return viewModel
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

struct MasterNodeView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewController: MasterNodeViewController
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return viewController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
