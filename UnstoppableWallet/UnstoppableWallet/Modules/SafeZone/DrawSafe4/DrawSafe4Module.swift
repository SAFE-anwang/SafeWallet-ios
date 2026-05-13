import UIKit
import SwiftUI

struct DrawSafe4Module {
    
    static func viewModel() -> DrawSafe4ViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }

        let provider = DrawSafe4Provider(networkManager: Core.shared.networkManager)
        let service = DrawSafe4Service(provider: provider, evmKit: evmKitWrapper.evmKit)
        let viewModel = DrawSafe4ViewModel(service: service)
        return viewModel
    }
}

struct DrawSafe4View: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: DrawSafe4ViewModel
    @Binding var isPresented: Bool
    
    func makeUIViewController(context _: Context) -> UIViewController {
        let viewController = DrawSafe4ViewController(viewModel: viewModel)
        let navigationController = ThemeNavigationController(rootViewController: viewController)
        viewController.onDismiss = {
            isPresented = false
        }
        return navigationController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
