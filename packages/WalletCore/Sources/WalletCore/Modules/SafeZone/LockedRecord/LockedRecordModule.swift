import Foundation
import SwiftUI
import UIKit
import EvmKit

class LockedRecordModule {

//    static func viewController(nav: UINavigationController) -> UIViewController? {
//        guard let evmKitWrapper = ChildWalletBridge.shared.activeSafe4EvmKitWrapper() else {
//            return nil
//        }
//        guard let privateKey = evmKitWrapper.signer?.privateKey else {
//            return nil
//        }
//
//        let service = LockedRecordService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
//        let viewModel = LockedRecordViewModel(service: service,
//                                              lockedStorage: storage.lockedRecoardStorage
//        )
//
//        let viewController = LockedRecordView(viewModel: viewModel, uiNavController: nav)
//            .toViewController()
//
//        return viewController
//    }

    static func viewModel() -> LockedRecordViewModel? {
        guard let evmKitWrapper = ChildWalletBridge.shared.activeSafe4EvmKitWrapper() else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }

        let service = LockedRecordService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        guard let storage = try? Core.shared.safe4StorageManager.scoped(service.cacheScope) else {
            HudHelper.instance.show(banner: .error(string: "error".localized))
            return nil
        }
        let viewModel = LockedRecordViewModel(service: service,
                                              lockedStorage: storage.lockedRecoardStorage
        )
        return viewModel
    }
}
