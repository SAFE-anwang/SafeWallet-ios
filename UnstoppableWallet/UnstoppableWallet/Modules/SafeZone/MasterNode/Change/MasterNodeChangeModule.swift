import UIKit
import SwiftUI
import BigInt
import EvmKit

struct MasterNodeChangeModule {
    static func viewModel(viewItem: MasterNodeViewModel.ViewItem) -> MasterNodeChangeViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = MasterNodeChangeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeChangeViewModel(service: service, viewItem: viewItem)
        return viewModel
    }
}
struct MasterNodeChangeView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: MasterNodeChangeViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let vc = MasterNodeChangeViewController(viewModel: viewModel)
        return ThemeNavigationController(rootViewController: vc)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
