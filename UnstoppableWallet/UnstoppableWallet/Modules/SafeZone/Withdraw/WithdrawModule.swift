import Foundation
import UIKit
import EvmKit
import MarketKit

class WithdrawModule {
    
    static func viewModel(type: SafeWithdrawType) -> WithdrawViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = WithdrawViewService(type: type, privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = WithdrawViewModel(service: service,
                                          withdrawLockedStorage: Core.shared.safe4StorageManager.withdrawLockedStorage
        )
        return viewModel
    }
}

enum SafeWithdrawType: Int {
    case masterNode
    case superNode
    case proposal
    case voteLocked
    
    var title: String {
        switch self {
        case .masterNode: "safe_zone.row.masterNode".localized + "safe_zone.safe4.withdraw".localized
        case .superNode: "safe_zone.row.superNode".localized + "safe_zone.safe4.withdraw".localized
        case .proposal: "safe_zone.row.proposal".localized + "safe_zone.safe4.withdraw".localized
        case .voteLocked: "safe_zone.vote_locked".localized + "safe_zone.safe4.withdraw".localized
        }
    }
}
