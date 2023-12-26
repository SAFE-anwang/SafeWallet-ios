import Foundation
import UIKit
import EvmKit
import MarketKit
import ComponentKit

class Safe4Module {
    
    static func handlerSafe2eth(chainType: ChainType) -> UIViewController? {
        let walletList = App.shared.walletManager.activeWallets
        var safeWallet: Wallet?
        var wsafeWallet: Wallet?
        var chain: Chain?
        
        for wallet in walletList {
            if wallet.coin.uid == safeCoinUid {
                if wallet.token.blockchain.type == .safe {
                    safeWallet = wallet
                    
                } else if chainType == .ETH, wallet.token.blockchain.type == .ethereum {
                    wsafeWallet = wallet
                    chain = .ethereum
                    
                } else if chainType == .BSC, wallet.token.blockchain.type == .binanceSmartChain {
                    wsafeWallet = wallet
                    chain = .binanceSmartChain
                    
                } else if chainType == .MATIC, wallet.token.blockchain.type == .polygon {
                    wsafeWallet = wallet
                    chain = .polygon
                }
            }
        }
        
        guard let safeWallet = safeWallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        
        guard let wsafeWallet = wsafeWallet else {
            var error: String?
            if chainType == .ETH {
                error = "safe_zone.send.openCoin".localized("SAFE ERC20")
            } else if chainType == .BSC {
                error = "safe_zone.send.openCoin".localized("SAFE BEP20")
            }else if chainType == .MATIC {
                error = "safe_zone.send.openCoin".localized("SAFE POLYGON")
            }
            HudHelper.instance.show(banner: .error(string: error ?? ""))
            return nil
        }
        guard let account = App.shared.accountManager.activeAccount else { return nil }
        if let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: safeWallet), state == .synced {
            
            guard let adapter = App.shared.adapterManager.adapter(for: safeWallet) else { return nil }
            
            guard let ethAdapter = App.shared.adapterManager.adapter(for: wsafeWallet) else { return nil }
            
            var contractAddress: Address?
            var reciverAddress: Address?
            
            do {
                if let chain = chain {
                    let raw = try WSafeKit(chain: chain).getSafeConvertAddress()
                    contractAddress = Address(raw: raw)
                }
            }catch {}
            
            if  let depositAdapter = App.shared.adapterManager.depositAdapter(for: wsafeWallet) {
                reciverAddress = Address(raw: depositAdapter.receiveAddress.address)
            }
            
            switch (adapter, ethAdapter){
            case (let adapter as ISendSafeCoinAdapter, let ethAdapter as ISendEthereumAdapter):
                let data = Safe4Data(wsafeWallet: wsafeWallet, safeWallet: safeWallet, isETH: chainType == .ETH, isMatic: chainType == .MATIC, contractAddress: contractAddress, reciverAddress: reciverAddress)
                return SendModule.wsafeViewController(token: safeWallet.token, mode: .send, adapter: adapter, ethAdapter: ethAdapter, data: data)
            default: return nil
            }            
        }else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))            
            return nil
        }
    }
    
    static func handlerEth2safe(chainType: ChainType) -> UIViewController? {
        let walletList = App.shared.walletManager.activeWallets
        var safeWallet: Wallet?
        var wsafeWallet: Wallet?
        var chain: Chain?
        
        for wallet in walletList {
            if wallet.coin.uid == safeCoinUid {
                if wallet.token.blockchain.type == .safe {
                    safeWallet = wallet
                    
                } else if chainType == .ETH, wallet.token.blockchain.type == .ethereum {
                    wsafeWallet = wallet
                    chain = .ethereum
                    
                } else if chainType == .BSC, wallet.token.blockchain.type == .binanceSmartChain {
                    wsafeWallet = wallet
                    chain = .binanceSmartChain
                    
                } else if chainType == .MATIC, wallet.token.blockchain.type == .polygon {
                    wsafeWallet = wallet
                    chain = .polygon
                }
            }
        }
        guard let safeWallet = safeWallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        
        guard let wsafeWallet = wsafeWallet else {
            var error: String?
            if chainType == .ETH {
                error = "safe_zone.send.openCoin".localized("SAFE ERC20")
            } else if chainType == .BSC {
                error = "safe_zone.send.openCoin".localized("SAFE BEP20")
            }else if chainType == .MATIC {
                error = "safe_zone.send.openCoin".localized("SAFE POLYGON")
            }
            HudHelper.instance.show(banner: .error(string: error ?? ""))
            return nil
        }
        guard let account = App.shared.accountManager.activeAccount else { return nil }
        if let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: wsafeWallet), state == .synced {
                        
            var contractAddress: Address?
            var reciverAddress: Address?
            do {
                if let chain = chain {
                    let raw = try WSafeKit(chain: chain).getContractAddress()
                    contractAddress = Address(raw: raw)
                }
            }catch {}
            
            if  let depositAdapter = App.shared.adapterManager.depositAdapter(for: safeWallet) {
                reciverAddress = Address(raw: depositAdapter.receiveAddress.address)
            }
            
            let data = Safe4Data(wsafeWallet: wsafeWallet, safeWallet: safeWallet, isETH: chainType == .ETH, isMatic: chainType == .MATIC, contractAddress: contractAddress, reciverAddress: reciverAddress)
            return SendEvmModule.wsafeViewController(wallet: wsafeWallet, data: data)
            
        }else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
    }
    
    static func handlerLineLock() -> UIViewController? {
        let walletList = App.shared.walletManager.activeWallets
        var safeWallet: Wallet?
        
        for wallet in walletList {
            if wallet.coin.uid == safeCoinUid {
                if wallet.token.blockchain.type == .safe, wallet.token.coin.uid == safeCoinUid {
                    safeWallet = wallet
                }
            }
        }
        
        guard let safeWallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = App.shared.accountManager.activeAccount else { return nil }
        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: safeWallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
        
        guard let adapter = App.shared.adapterManager.adapter(for: safeWallet) else { return nil }
        
        var reciverAddress: Address?

        if  let depositAdapter = App.shared.adapterManager.depositAdapter(for: safeWallet) {
            reciverAddress = Address(raw: depositAdapter.receiveAddress.address)
        }
        
        switch adapter {
        case let adapter as ISendSafeCoinAdapter:
            return SendModule.lineLockViewController(token: safeWallet.token, mode: .send, adapter: adapter, reciverAddress: reciverAddress)
        default: return nil
        }
        
    }
    
}


enum ChainType {
    case ETH, BSC, MATIC
}

struct Safe4Data {
    var wsafeWallet: Wallet?
    var safeWallet: Wallet?
    var isETH: Bool
    var isMatic: Bool
    var contractAddress: Address?
    var reciverAddress: Address?

}
