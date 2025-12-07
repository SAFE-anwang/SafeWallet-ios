import UIKit
import SwiftUI

struct SuperNodeRegisterModule {
    static func viewController() -> UIViewController? {
        
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return SuperNodeRegisterViewController(viewModel: viewModel)
    }
    
    static func viewModel() -> SuperNodeRegisterViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return viewModel
    }
}

struct SuperNodeRegisterView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: SuperNodeRegisterViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return ThemeNavigationController(rootViewController: SuperNodeRegisterViewController(viewModel: viewModel))
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
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
