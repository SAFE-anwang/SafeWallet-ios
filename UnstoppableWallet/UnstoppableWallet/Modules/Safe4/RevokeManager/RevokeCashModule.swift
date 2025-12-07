import Foundation
import MarketKit
import UIKit

struct RevokeCashModule {
    
    static func viewModel(blockchainType: BlockchainType) -> RevokeCashViewModel? {
        guard let chain = try? Core.shared.evmBlockchainManager.chain(blockchainType: blockchainType) else { return nil }
        guard let account = Core.shared.accountManager.activeAccount else { return nil }
        guard let address = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper(account: account, blockchainType: blockchainType).evmKit.address else { return nil }
        let viewModel = RevokeCashViewModel(walletAddress: address, chain: chain, account: account)
        return viewModel
    }
    
}
