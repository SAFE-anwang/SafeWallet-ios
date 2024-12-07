import UIKit

struct SuperNodeRegisterModule {
    static func viewController() -> UIViewController? {
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return SuperNodeRegisterViewController(viewModel: viewModel)
    }
}

enum SuperNodeInputType {
    case address
    case name
    case ENODE
    case desc
    
    var title: String {
        switch self {
        case .address: return "safe_zone.safe4.node.super.address.wallet".localized
        case .name: return "safe_zone.safe4.node.detail.name".localized
        case .ENODE: return "ENODE".localized
        case .desc: return "safe_zone.safe4.node.desc.title".localized
        }
    }
    
    var placeholder: String {
        switch self {
        case .address: return "safe_zone.safe4.node.super.input.address".localized
        case .name: return "safe_zone.safe4.node.super.input.name".localized
        case .ENODE: return "safe_zone.safe4.node.super.input.enode".localized
        case .desc: return "safe_zone.safe4.node.super.input.desc".localized
        }
    }
    
    var keyboardType: UIKeyboardType {
        .default
    }
}
