import Foundation
import SwiftUI
import UIKit
import EvmKit

class LockedRecordModule {

//    static func viewController(nav: UINavigationController) -> UIViewController? {
//        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
//            return nil
//        }
//        guard let privateKey = evmKitWrapper.signer?.privateKey else {
//            return nil
//        }
//        
//        let service = LockedRecordService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
//        let viewModel = LockedRecordViewModel(service: service,
//                                              lockedStorage: Core.shared.safe4StorageManager.lockedRecoardStorage
//        )
//        
//        let viewController = LockedRecordView(viewModel: viewModel, uiNavController: nav)
//            .toViewController()
//        
//        return viewController
//    }
    
    static func viewModel() -> LockedRecordViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = LockedRecordService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = LockedRecordViewModel(service: service,
                                              lockedStorage: Core.shared.safe4StorageManager.lockedRecoardStorage
        )
        return viewModel
    }
}

