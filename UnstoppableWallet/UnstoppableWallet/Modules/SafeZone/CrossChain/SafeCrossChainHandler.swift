import EvmKit
import Foundation
import MarketKit
import SwiftUI
import BigInt

class SafeCrossChainHandler {
    private let crossChain: SAFE_CrossChain
    private let direction: CrossChainToken.Direction
    private var baseWallet: Wallet?
    
    init(crossChain: SAFE_CrossChain, direction: CrossChainToken.Direction) throws {
        self.crossChain = crossChain
        self.direction = direction
        
        switch direction {
        case .SAFE_CrossChain_to_other:
            if let wallet = activeWallets.filter({
                $0.token.type == .native &&
                $0.token.blockchain.type == .safe4
            }).first {
                self.baseWallet = wallet
            } else {
                throw CrossChainWalletError.openWallet(openTokenTips)
            }
        case .other_CrossChain_to_SAFE:
            if let wallet = activeWallets.filter({
                $0.coin.uid == crossChain.coinUid &&
                $0.token.blockchain.type == crossChain.blockchainType
            }).first {
                self.baseWallet = wallet
            } else {
                throw CrossChainWalletError.openWallet(openTokenTips)
            }

        }


    }
    
    var activeWallets: [Wallet] {
        Core.shared.walletManager.activeWallets
    }
    
    var openTokenTips: String {
        switch direction {
        case .SAFE_CrossChain_to_other: return "safe_zone.send.openCoin".localized("SAFE")
        case .other_CrossChain_to_SAFE: return crossChain.errorTips
        }
    }
}

extension SafeCrossChainHandler: ICrossChainHandler {
    var minAmount: Decimal {
        0.1
    }
    
    var wallet: Wallet {
        baseWallet!
    }
    
    var receiverBlockchainType: BlockchainType {
        crossChain.blockchainType
    }
    
    var crossChainContract: String {
        switch direction {
        case .SAFE_CrossChain_to_other: return crossChain.safe_CrossChainContract
        case .other_CrossChain_to_SAFE: return crossChain.wSafe_CrossChainContract
        }
    }
    
    var navTitle: String {
        switch direction {
        case .SAFE_CrossChain_to_other: return "SAFE => SAFE \(crossChain.name)"
        case .other_CrossChain_to_SAFE: return "SAFE \(crossChain.name) => SAFE"
        }
    }
    
    // address: 跨链接收人 address
    func sendData(amount: Decimal, address: String) -> SendDataResult {
        guard let evmAmount = BigUInt(amount.hs.roundedString(decimal: wallet.token.decimals)) else {
            return .invalid(cautions: [])
        }
        guard let _ = try? EvmKit.Address(hex: address) else {
            return .invalid(cautions: [])
        }
        let transactionData = transactionData(amount: evmAmount, to: address)
        return .valid(sendData: .crossChain(baseWallet: wallet, transactionData: transactionData))
    }
}

extension SafeCrossChainHandler {
    
    /// - Parameters:
    ///   - amount: 跨链金额
    ///   - to: 跨链接收人 address
    func transactionData(amount: BigUInt, to: String) -> TransactionData {
        let crossChainAddress = try! EvmKit.Address(hex: crossChainContract)
        switch direction {
        case .SAFE_CrossChain_to_other:
            return TransactionData(to: crossChainAddress, value: amount, input: (crossChain.wsafeAddressPrefix + to).hs.data)
            
        case .other_CrossChain_to_SAFE:
            let input = Web3jUtils.getEth2safeTransactionInput(amount: amount, toAddressHex: to) ??  Data()
            return TransactionData(to: crossChainAddress, value: .zero, input: input)
        }
    }
}

enum CrossChainWalletError: Error {
    case openWallet(String)
}

enum SAFE_CrossChain: CaseIterable {
    case ETH
    case BSC
    case POL
    
    var coinUid: String {
        switch self {
        case .ETH, .BSC, .POL: return safe4CoinUid
        }
    }
    
    var blockchainType: BlockchainType {
        switch self {
        case .ETH: return .ethereum
        case .BSC: return .binanceSmartChain
        case .POL: return .polygon
        }
    }
    
    var name: String {
        switch self {
        case .ETH: return "ERC20"
        case .BSC: return "BEP20"
        case .POL: return "Polygon POS"
        }
    }
        
    var errorTips: String {
        switch self {
        case .ETH: return "safe_zone.send.openCoin".localized("SAFE ERC20")
        case .BSC: return "safe_zone.send.openCoin".localized("SAFE BEP20")
        case .POL: return "safe_zone.send.openCoin".localized("SAFE MATIC")
        }
    }
    
    // wsafe -> safe
    var wSafe_CrossChainContract: String  {
        switch self {
        case .ETH: return "0xee9c1ea4dcf0aaf4ff2d78b6ff83aa69797b65eb"
        case .BSC: return "0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1" //BSC正式环境
        case .POL: return "0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779"
        }
    }

    // safe -> wsafe
    var safe_CrossChainContract: String {
        switch self {
        case .ETH: return "0x30728eBa408684D167CF59828261Db8A2A59E8C7"
        case .BSC: return "0x471B9eB32a6750b0356E0C80294Ee035C4bdF60B"
        case .POL: return "0x960Bb626aba915c242301EC47948Ba475CDeC090"
        }
    }

    var wsafeAddressPrefix: String {
        switch self {
        case .ETH: return "eth:"
        case .BSC: return "bsc:"
        case .POL: return "matic:"
        }
    }
    
    public enum UnsupportedChainError: Error {
        case noWethAddress
        case noSafeAddress
        case noSafeNetType
    }
}
