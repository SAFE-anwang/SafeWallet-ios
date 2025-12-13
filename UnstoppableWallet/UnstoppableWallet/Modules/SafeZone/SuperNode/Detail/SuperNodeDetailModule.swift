import UIKit
import SwiftUI

struct SuperNodeDetailModule {
    static func viewModel(viewItem: SuperNodeViewModel.ViewItem) -> SuperNodeDetailViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let viewModel = SuperNodeDetailViewModel(nodeViewItem: viewItem, service: SuperNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit), superNodeLockRecordStorage: Core.shared.safe4StorageManager.superNodeLockRecordStorage)
        return viewModel
    }
}

struct SuperNodeDetailView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: SuperNodeDetailViewModel
    let viewType: SuperNodeDetailViewModel.ViewType
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let vc = SuperNodeDetailViewController(viewModel: viewModel, viewType: viewType)
        return ThemeNavigationController(rootViewController: vc)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
