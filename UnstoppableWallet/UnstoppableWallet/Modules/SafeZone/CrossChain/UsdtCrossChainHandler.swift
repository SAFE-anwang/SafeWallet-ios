import EvmKit
import Foundation
import MarketKit
import SwiftUI
import BigInt

class UsdtCrossChainHandler {
    private let crossChain: USDT_CrossChain
    private let direction: CrossChainToken.Direction
    private var baseWallet: Wallet?
    
    init(crossChain: USDT_CrossChain, direction: CrossChainToken.Direction) throws {
        self.crossChain = crossChain
        self.direction = direction
        
        switch direction {
        case .SAFE_CrossChain_to_other:
            if let wallet = activeWallets.filter({$0.token.type == .eip20(address: safe4UsdtContract) && $0.token.blockchain.type == .safe4}).first {
                self.baseWallet = wallet
            } else {
                throw CrossChainWalletError.openWallet(openTokenTips)
            }
        case .other_CrossChain_to_SAFE:
            if let wallet = activeWallets.filter({
                $0.token.type == crossChain.tokenType &&
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
        case .SAFE_CrossChain_to_other: return "safe_zone.send.openCoin".localized("USDT SAFE")
        case .other_CrossChain_to_SAFE: return crossChain.errorTips
        }
    }
}

extension UsdtCrossChainHandler: ICrossChainHandler {

    var wallet: Wallet {
        self.baseWallet!
    }
    
    var receiverBlockchainType: BlockchainType {
        crossChain.blockchainType
    }
    
    var minAmount: Decimal {
        0.1
    }
    
    var crossChainContract: String {
        switch direction {
        case .SAFE_CrossChain_to_other: return crossChain.safe_CrossChainContract
        case .other_CrossChain_to_SAFE: return crossChain.wsafe_CrossChainContract
        }
    }
    
    var navTitle: String {
        switch direction {
        case .SAFE_CrossChain_to_other: return "USDT SAFE => USDT \(crossChain.name)"
        case .other_CrossChain_to_SAFE: return "USDT \(crossChain.name) => USDT SAFE"
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
        let transactionData = transactionData(amount: evmAmount, recipient: address)
        return .valid(sendData: .crossChain(baseWallet: wallet, transactionData: transactionData))
    }
}

extension UsdtCrossChainHandler {
    
    /// - Parameters:
    ///   - amount: 跨链金额
    ///   - to: 跨链接收人 address
    func transactionData(amount: BigUInt, recipient: String) -> TransactionData {
        switch direction {
        case .SAFE_CrossChain_to_other:
            let input = Web3jUtils.send_USDT_SAFE4_TransactionInput(amount: amount, address: recipient, network: crossChain.netType) ??  Data()
            let to = try! EvmKit.Address(hex: SAFE4USDT_Contract)
            return TransactionData(to: to, value: .zero, input: input)

        case .other_CrossChain_to_SAFE:
            let inputTo = try! EvmKit.Address(hex: crossChain.wsafe_CrossChainContract)
            let input = Web3jUtils.send_USDT_ETH_TransactionInput(address: inputTo, amount: amount)
            let extraData = "safe4:\(recipient)".hs.data
            let to = try! EvmKit.Address(hex: crossChain.safe_CrossChainContract)
            return TransactionData(to: to, value: .zero, input: ((input ?? Data()) + extraData))
        }
    }
}

let SAFE4USDT_Contract = "0x9C1246a4BB3c57303587e594a82632c3171662C9"
let USDT_EthContract = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
let USDT_BscContract = "0x55d398326f99059fF775485246999027B3197955"
let USDT_TronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
let USDT_SolContract = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

enum USDT_CrossChain: CaseIterable {
    case ETH
    case BSC
    case TRON
    case SOL

    var tokenType: TokenType {
        switch self {
        case .ETH: return .eip20(address: USDT_EthContract.lowercased())
        case .BSC: return .eip20(address: USDT_BscContract.lowercased())
        case .TRON: return .eip20(address: USDT_TronContract.lowercased())
        case .SOL: return .eip20(address: USDT_SolContract.lowercased())
        }
    }
    
    var blockchainType: BlockchainType {
        switch self {
        case .ETH: return .ethereum
        case .BSC: return .binanceSmartChain
        case .TRON: return .tron
        case .SOL: return .solana
        }
    }
    
    var name: String {
        switch self {
        case .ETH: return "ERC20"
        case .BSC: return "BEP20"
        case .TRON: return "TRC20"
        case .SOL: return "SOLANA"
        }
    }
        
    var errorTips: String {
        switch self {
        case .ETH: return "safe_zone.send.openCoin".localized("USDT ERC20")
        case .BSC: return "safe_zone.send.openCoin".localized("BSC-USDT BEP20")
        case .TRON: return "safe_zone.send.openCoin".localized("USDT TRC20")
        case .SOL: return "safe_zone.send.openCoin".localized("USDT SOLANA")
        }
    }
    
    // usdt safe -> wusdt
    var safe_CrossChainContract: String  {
        switch self {
        case .ETH: return "0xdAC17F958D2ee523a2206206994597C13D831ec7" //√
        case .BSC: return "0x55d398326f99059fF775485246999027B3197955" //√
//        case .BSC: return "0xa3d8077c3a447049164e60294c892e5e4c7f3ad2" //BSC Test Ev
        case .TRON: return "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        case .SOL: return "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
        }
    }

    // wusdt -> usdt safe
    var wsafe_CrossChainContract: String {
        switch self {
        case .ETH: return "0xbB92E5E0120fe5345D5b5d36fcCdAfA391976622"
        case .BSC: return "0xbB92E5E0120fe5345D5b5d36fcCdAfA391976622"
        case .TRON: return "TJefpssM9uEuUhrxnmGVotw4GRem63uXFr"
        case .SOL: return "E7gFBw75dnXad9GqYW5EVgCNAJ85uCe29L4x6iR4BAqQ"
        }
    }
    
    var netType: String {
        switch self {
        case .ETH: return "eth"
        case .BSC: return "bsc"
        case .TRON: return "tron"
        case .SOL: return "sol"
        }
    }
}
