import UIKit
import SwiftUI
import EvmKit
import BigInt
import Web3Core
import web3swift

struct AddLockDaysModule {
        
    static func viewModel(ids: [BigUInt]) -> AddLockDaysViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = AddLockDaysService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = AddLockDaysViewModel(service: service, ids: ids)
        return viewModel
    }
    
    
}

enum AddLockType {
    case address(String)
    case ids([BigUInt])
}

