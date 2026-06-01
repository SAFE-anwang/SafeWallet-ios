import UIKit
import BigInt
import EvmKit
import SwiftUI

struct SuperNodeModule {
    static func tabViewModel() -> SuperNodeTabViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SuperNodeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeTabViewModel(service: service)
        return viewModel
    }

    @MainActor
    static func viewModel(type: SuperNodeType, evmKit: EvmKit.Kit, privateKey: Data) -> SuperNodeViewModel {
        let service = SuperNodeService(privateKey: privateKey, evmKit: evmKit)
        let viewModel = SuperNodeViewModel(service: service, type: type)
        return viewModel
    }
        
    enum Tab: Int, CaseIterable {
        case all
        case mine
        
        var title: String {
            switch self {
            case .all: return "safe_zone.safe4.node.super.list".localized
            case .mine: return "safe_zone.safe4.node.super.mine".localized
            }
        }
    }
    
    enum SuperNodeType {
        case All
        case Mine
    }
}

struct SuperNodeView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: SuperNodeViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return SuperNodeViewController(viewModel: viewModel)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
