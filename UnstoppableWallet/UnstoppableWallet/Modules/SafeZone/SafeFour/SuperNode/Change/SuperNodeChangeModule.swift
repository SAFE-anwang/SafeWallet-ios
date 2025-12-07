import UIKit
import SwiftUI
import BigInt
import EvmKit

struct SuperNodeChangeModule {
    static func viewModel(viewItem: SuperNodeViewModel.ViewItem) -> SuperNodeChangeViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeChangeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeChangeViewModel(service: service, viewItem: viewItem)
        return viewModel
    }
}

struct SuperNodeChangeView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: SuperNodeChangeViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let vc = SuperNodeChangeViewController(viewModel: viewModel)
        return ThemeNavigationController(rootViewController: vc)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
