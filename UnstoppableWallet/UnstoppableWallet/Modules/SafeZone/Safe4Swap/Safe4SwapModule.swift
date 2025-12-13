import Foundation
import UIKit
import EvmKit
import MarketKit
import SwiftUI

class Safe4SwapModule {
    static let gasLimit: Int = 100000

    static func viewModel() -> Safe4SwapViewModel? {
        let walletList = Core.shared.walletManager.activeWallets
        
        guard let tokenIn = walletList.filter({$0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4 && $0.token.type == .native}).first?.token else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let tokenOut = walletList.filter({$0.token.blockchain.type == .safe4 && $0.token.type == .eip20(address: "0x0000000000000000000000000000000000001101")}).first?.token else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE SRC20")))
            return nil
        }
        let viewModel = Safe4SwapViewModel(tokenIn: tokenIn, tokenOut: tokenOut)
        return viewModel
    }
}

extension Safe4SwapViewModel {
    static func instance(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Safe4SwapViewModel {
        return Safe4SwapViewModel(tokenIn: tokenIn, tokenOut: tokenOut)
    }
}

enum Safe4SwapSendData {
    case evm(blockchainType: BlockchainType, transactionData: TransactionData)
}
