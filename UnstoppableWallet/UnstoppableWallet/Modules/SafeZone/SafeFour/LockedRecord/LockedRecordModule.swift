import Foundation
import SwiftUI
import Foundation
import UIKit
import EvmKit
import ComponentKit

class LockedRecordModule {

    static func viewController(nav: UINavigationController) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = LockedRecordService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = LockedRecordViewModel(service: service,
                                              lockedStorage: App.shared.safe4StorageManager.lockedRecoardStorage,
                                              proposalStorage: App.shared.safe4StorageManager.proposalLockedStorage
        )
        
        let viewController = LockedRecordView(viewModel: viewModel, uiNavController: nav)
            .toViewController()
        
        return viewController
    }
    
}

