import Foundation
import UIKit
import EvmKit
import MarketKit
import SwiftUI

struct CrossChainModule {

    static func crossChainViewModel(token: CrossChainToken) -> CrossPreSendViewModel? {
        
        let crossChainHandler: ICrossChainHandler
        do {
            switch token {
            case let .SAFE(crossChain, direction):
                crossChainHandler = try SafeCrossChainHandler(crossChain: crossChain, direction: direction)
                
            case let .USDT(crossChain, direction):
                crossChainHandler = try UsdtCrossChainHandler(crossChain: crossChain, direction: direction)
            }

        }catch {
            if let _error = error as? CrossChainWalletError, case let .openWallet(text) = _error {
                HudHelper.instance.show(banner: .error(string: text))
            }
            return nil
        }
        
        let resolvedAddress = ResolvedAddress(address: crossChainHandler.crossChainContract, issueTypes: [])
        let handler = SendHandlerFactory.preSendHandler(wallet: crossChainHandler.wallet, address: resolvedAddress)
        let viewModel = CrossPreSendViewModel(handler: handler, crossChainHandler: crossChainHandler, resolvedAddress: resolvedAddress, amount: nil, memo: nil)
        return viewModel
    }
}

enum CrossChainToken {
    case SAFE(chain: SAFE_CrossChain, direction: Direction)
    case USDT(chain: USDT_CrossChain, direction: Direction)
    
    enum Direction {
        // SFAE cross-chain to other chain
        case SAFE_CrossChain_to_other
        // other chain cross-chain to SFAE
        case other_CrossChain_to_SAFE
    }

}

