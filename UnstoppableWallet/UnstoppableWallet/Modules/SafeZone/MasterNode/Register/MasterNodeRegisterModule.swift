import UIKit
import SwiftUI

struct MasterNodeRegisterModule {

    static func viewModel() -> MasterNodeRegisterViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = MasterNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return viewModel
    }
}

struct MasterNodeRegisterView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: MasterNodeRegisterViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return ThemeNavigationController(rootViewController: MasterNodeRegisterViewController(viewModel: viewModel))
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
