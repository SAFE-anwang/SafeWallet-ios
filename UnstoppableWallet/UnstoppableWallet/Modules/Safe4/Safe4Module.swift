import Foundation
import UIKit
import EvmKit
import MarketKit
import ComponentKit
import SwiftUI
import web3swift

class Safe4Module {
    
    static func handlerCrossChain(wsafeType: WSafeChainType, crossChainType: CrossChainType, isSafe4: Bool) -> UIViewController? {
        
        guard let account = App.shared.accountManager.activeAccount else { return nil }

        let walletList = App.shared.walletManager.activeWallets
        
        let safeWallet = walletList.filter{$0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4 && $0.token.type == .native}.first
        let wsafeWallet = walletList.filter{$0.coin.uid == safeCoinUid && $0.token.blockchain.type == wsafeType.blockchainType}.first
        
        guard let safeWallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        
        guard let wsafeWallet else {
            HudHelper.instance.show(banner: .error(string: wsafeType.errorTips))
            return nil
        }
        
        let activeAccountWallet: Wallet
        
        switch crossChainType {
        case .safeCrossToWSafe: activeAccountWallet = safeWallet
        case .wsafeCrossToSafe: activeAccountWallet = wsafeWallet
        }
        
        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: activeAccountWallet), state == .synced  else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
            
        
        let contractAddress: Address
        do {
            let wSafeKit = WSafeKit(chain: wsafeType.chain)
            switch crossChainType {
            case .safeCrossToWSafe:
                let raw = try wSafeKit.getSafeConvertAddress()
                contractAddress = Address(raw: raw)
                
            case .wsafeCrossToSafe:
                let raw = try wSafeKit.getContractAddress()
                contractAddress = Address(raw: raw)
            }
        }catch {
            return nil
        }
        
        var reciverAddress: Address?
        if let depositAdapter = App.shared.adapterManager.depositAdapter(for: activeAccountWallet) {
            reciverAddress = Address(raw: depositAdapter.receiveAddress.address)
        }
        
        guard let reciverAddress else {  return nil }
        let crossChainInfo = SafeCrossChainInfo(wsafeWallet: wsafeWallet,
                                      safeWallet: safeWallet,
                                      contractAddress: contractAddress,
                                      reciverAddress: reciverAddress,
                                      crossChainType: crossChainType
        )

        if case .safeCrossToWSafe = crossChainType {
            guard let adapter = App.shared.adapterManager.adapter(for: safeWallet) else { return nil }
            switch adapter {
            case let adapter as ISendEthereumAdapter:
                return SendEvmModule.safe4ViewController(token: safeWallet.token, wsafeChainType: wsafeType, safeAdapter: adapter, crossChainInfo: crossChainInfo)
            default: return nil
            }
        }
        
        if case .wsafeCrossToSafe = crossChainType {
            guard let wsafeAdapter = App.shared.adapterManager.adapter(for: wsafeWallet) else { return nil }
            switch wsafeAdapter {
            case let wsafeAdapter as ISendEthereumAdapter:
                return SendEvmModule.wsafeViewController(token: wsafeWallet.token, wsafeAdapter: wsafeAdapter, crossChainInfo: crossChainInfo)
            default: return nil
            }

        }
        return nil
    }
    
    
    
//    static func handlerLineLock() -> UIViewController? {
//        let walletList = App.shared.walletManager.activeWallets
//        var safeWallet: Wallet?
//        
//        for wallet in walletList {
//            if wallet.coin.uid == safe4CoinUid {
//                if wallet.token.blockchain.type == .safe4, wallet.token.coin.uid == safe4CoinUid {
//                    safeWallet = wallet
//                }
//            }
//        }
//        
//        guard let safeWallet else {
//            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
//            return nil
//        }
//        guard let account = App.shared.accountManager.activeAccount else { return nil }
//        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: safeWallet), state == .synced else {
//            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
//            return nil
//        }
//        
//        guard let adapter = App.shared.adapterManager.adapter(for: safeWallet) else { return nil }
//        
//        var reciverAddress: Address?
//
//        if  let depositAdapter = App.shared.adapterManager.depositAdapter(for: safeWallet) {
//            reciverAddress = Address(raw: depositAdapter.receiveAddress.address)
//        }
//        
//        switch adapter {
//        case let adapter as ISendSafeCoinAdapter:
//            return SendModule.lineLockViewController(token: safeWallet.token, mode: .send, adapter: adapter, reciverAddress: reciverAddress)
//        default: return nil
//        }
//        
//    }
    
}


enum WSafeChainType {
    case ETH, BSC, MATIC
    
    var chain: Chain {
        switch self {
        case .ETH: return Chain.ethereum
        case .BSC: return Chain.binanceSmartChain
        case .MATIC: return Chain.polygon
        }
    }
    
    var name: String {
        switch self {
        case .ETH: return "ERC20"
        case .BSC: return "BEP20"
        case .MATIC: return "MATIC"
        }
    }
    
    var blockchainType: BlockchainType {
        switch self {
        case .ETH: return .ethereum
        case .BSC: return .binanceSmartChain
        case .MATIC: return .polygon
        }
    }
    
    var errorTips: String {
        switch self {
        case .ETH: return "safe_zone.send.openCoin".localized("SAFE ERC20")
        case .BSC: return "safe_zone.send.openCoin".localized("SAFE BEP20")
        case .MATIC: return "safe_zone.send.openCoin".localized("SAFE POLYGON")
        }
    }
}

enum CrossChainType {
    case safeCrossToWSafe
    case wsafeCrossToSafe
}
    
struct SafeCrossChainInfo {
    
    let wsafeWallet: Wallet
    let safeWallet: Wallet
    let contractAddress: Address
    let reciverAddress: Address
    let crossChainType: CrossChainType

    var fromWallet: Wallet {
        switch crossChainType {
        case .safeCrossToWSafe: return safeWallet
        case .wsafeCrossToSafe: return wsafeWallet
        }
    }
    
    var toWallet: Wallet {
        switch crossChainType {
        case .safeCrossToWSafe: return wsafeWallet
        case .wsafeCrossToSafe: return safeWallet
        }
    }
    
    var wsafeChainType: WSafeChainType? {
        switch wsafeWallet.token.blockchain.type {
        case .ethereum: return .ETH
        case .binanceSmartChain: return .BSC
        case .polygon: return .MATIC
        default: return nil
        }
    }
    
    var isSafe4CrossChain: Bool {
        (wsafeWallet.coin.uid == safe4CoinUid && wsafeWallet.token.blockchain.type == .safe4 && wsafeWallet.token.type == .native) ||
        (safeWallet.coin.uid == safe4CoinUid && safeWallet.token.blockchain.type == .safe4 && safeWallet.token.type == .native)
    }
    
    var navTitle: String {
        guard let type = wsafeChainType else { return "" }
        switch crossChainType {
        case .safeCrossToWSafe: return "\(fromWallet.token.coin.name) => \(fromWallet.token.coin.name) \(type.name)"
        case .wsafeCrossToSafe: return "\(fromWallet.token.coin.name) \(type.name) => \(fromWallet.token.coin.name)"
        }
    }
    
    var isMatic: Bool {
        wsafeWallet.token.blockchain.type == .polygon
    }

}

struct Safe4CrossChainView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    var viewController: UIViewController?
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        viewController ?? UIViewController()
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

extension web3swift.AccountManager.ContractType {
    
    static func contractType(value: Decimal) -> web3swift.AccountManager.ContractType? {
        if 0.1 ..< 1 ~= value {
            return .smallAmount_01
        }else if 0.01 ..< 0.1 ~= value {
            return .smallAmount_02
        }else if value >= 1 {
            return .native
        }
        return nil
    }
}
