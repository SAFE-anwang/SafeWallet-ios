import UIKit
import SwiftUI
import EvmKit
import ComponentKit
import BigInt
import Web3Core
import web3swift
import ThemeKit

struct AddLockDaysModule {
    
    static func viewController(ids: [BigUInt]) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = AddLockDaysService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = AddLockDaysViewModel(service: service, ids: ids)
        
        let viewController = AddLockDaysView(viewModel: viewModel).toViewController()
        return viewController
    }
}

enum AddLockType {
    case address(String)
    case ids([BigUInt])
}

