import UIKit
import ComponentKit

struct DrawSafe4Module {
    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }

        let provider = DrawSafe4Provider(networkManager: App.shared.networkManager)
        let service = DrawSafe4Service(provider: provider, evmKit: evmKitWrapper.evmKit)
        let viewModel = DrawSafe4ViewModel(service: service)
        return DrawSafe4ViewController(viewModel: viewModel)
    }
}
