import UIKit
import SwiftUI

struct MasterNodeDetailModule {
    static func viewModel(nodeType: Safe4NodeType, viewItem: MasterNodeViewModel.ViewItem) -> MasterNodeDetailViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
         let service = MasterNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeDetailViewModel(nodeType: nodeType, nodeViewItem: viewItem, service: service)
        return viewModel
    }
}

struct MasterNodeDetailView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: MasterNodeDetailViewModel
    let viewType: MasterNodeDetailViewModel.ViewType
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let vc = MasterNodeDetailViewController(viewModel: viewModel, viewType: viewType)
        return ThemeNavigationController(rootViewController: vc)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
