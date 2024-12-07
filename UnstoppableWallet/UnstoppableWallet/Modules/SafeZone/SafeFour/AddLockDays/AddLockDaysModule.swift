import UIKit
import EvmKit
import ComponentKit
import BigInt
import Web3Core
import web3swift
struct AddLockDaysModule {
    
    static func viewController(type: LockNodeType) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = AddLockDaysService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = AddLockDaysViewModel(service: service, type: type)
        let viewController = AddLockDaysViewController(viewModel: viewModel)
        return viewController
    }
}

enum LockNodeType {
    case masterNode(info: MasterNodeInfo)
    case superNode(info: SuperNodeInfo)
}
