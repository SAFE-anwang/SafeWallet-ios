import UIKit
import SwiftUI

struct SuperNodeDetailModule {
    static func viewModel(viewItem: SuperNodeViewModel.ViewItem) -> SuperNodeDetailViewModel? {
        guard let evmKitWrapper = ChildWalletBridge.shared.activeSafe4EvmKitWrapper() else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SuperNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        guard let storage = try? Core.shared.safe4StorageManager.scoped(service.cacheScope) else {
            HudHelper.instance.show(banner: .error(string: "error".localized))
            return nil
        }
        let viewModel = SuperNodeDetailViewModel(nodeViewItem: viewItem, service: service, superNodeLockRecordStorage: storage.superNodeLockRecordStorage)
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
