import Foundation
import SwiftUI
import Foundation
import UIKit
import EvmKit
import ComponentKit

class LockedRecoardModule {

    static func viewController(nav: UINavigationController) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = LockedRecoardService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = LockedRecoardViewModel(service: service)
        let viewController = LockedRecoardView(viewModel: viewModel, uiNavController: nav)
            .toViewController()
        
        return viewController
    }
    
}

