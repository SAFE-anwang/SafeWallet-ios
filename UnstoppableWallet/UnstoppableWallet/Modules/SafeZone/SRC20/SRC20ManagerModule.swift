import Foundation
import SwiftUI
import UIKit
import EvmKit
import MarketKit

class SRC20ManagerModule {

    static func viewModel() -> SRC20ManagerViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let provider = SyncSafe4TokensProvider(networkManager: Core.shared.networkManager)
        let tokensService = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey, lockAddress: evmKitWrapper.evmKit.receiveAddress.eip55), evmKit: evmKitWrapper.evmKit, storage: Core.shared.safe4CustomTokenStorage, marketKit: Core.shared.marketKit)
        let viewModel = SRC20ManagerViewModel(tokensService: tokensService)
        return viewModel
    }
    
    static func detailViewModel(token: Safe4CustomTokenRecord, type: SRC20EditType) -> (any ObservableObject)? {
        let walletList = Core.shared.walletManager.activeWallets
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SRC20Service(token: token, privateKey: privateKey, lockAddress: evmKitWrapper.evmKit.receiveAddress.eip55)
        
        switch type {
        case .edit:
            let viewModel = SRC20EditViewModel(token: token, service: service)
            return viewModel
            
        case .promotion:
            guard let safeWallet = walletList.filter({$0.token.isSafe4Native}).first else {
                HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
                return nil
            }
            guard let adapter = Core.shared.adapterManager.adapter(for: safeWallet) as? ISendEthereumAdapter else { return nil}
            let viewModel = SRC20PromotionViewModel(token: token, service: service, adapter: adapter)
            return viewModel
            
        case .additional:
            let viewModel = SRC20AdditionalViewModel(token: token, service: service)
            return viewModel
            
        case .destroy:
            guard let wsafeWallet = walletList.filter({ wallet in
                guard wallet.token.blockchain.type == .safe4 else {return false}
                switch wallet.token.type {
                case let .eip20(address):
                    return address.lowercased() == token.address.lowercased()
                default: return false
                }
            }).first else {
                HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized(token.symbol)))
                return nil
            }
            guard let adapter = Core.shared.adapterManager.adapter(for: wsafeWallet) as? ISendEthereumAdapter else { return nil}
            let viewModel = SRC20DestroyViewModel(token: token, service: service, adapter: adapter)
            return viewModel
        }
    }
}

enum SRC20EditType: String, Hashable {
    case edit
    case promotion
    case additional
    case destroy
    
    public static func == (lhs: SRC20EditType, rhs: SRC20EditType) -> Bool {
        switch (lhs, rhs) {
        case (.edit, .edit): return true
        case (.promotion, .promotion): return true
        case (.additional, .additional): return true
        case (.destroy, .destroy): return true
        default: return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .edit:
            hasher.combine("edit")
        case .promotion:
            hasher.combine("promotion")
        case .additional:
            hasher.combine("additional")
        case .destroy:
            hasher.combine("destroy")
        }
    }
    
}
