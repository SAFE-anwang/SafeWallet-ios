import Foundation
import EvmKit
import BigInt
import HsToolKit

public class WSafeKit {
    
    public enum UnsupportedChainError: Error {
        case noWethAddress
        case noSafeAddress
        case noSafeNetType
    }
    
    private let chain: Chain
    private let wsafeManager: WSafeManager
    
    public init(chain: Chain) {
        self.chain = chain
        self.wsafeManager = WSafeManager(chain: chain)
    }
    
    public func transactionData(amount: BigUInt,
                                to: String) -> TransactionData {
            wsafeManager.transactionData(amount: amount, to: to)
    }
    
    public func transactionDataSafe4(amount: BigUInt,
                                to: String) -> TransactionData {
            wsafeManager.transactionDataSafe4(amount: amount, to: to)
    }

    func getContractAddress() throws -> String {
        try wsafeManager.getContractAddress(chain: chain)
    }
    
    func getSafeConvertAddress() throws -> String {
        try wsafeManager.getSafeAddress(chain: chain)
    }

    func getSafeNetType() throws -> String {
        try wsafeManager.getSafeNetType(chain: chain)
    }
}

fileprivate class WSafeManager {
        
    private let chain: EvmKit.Chain

    init(chain: EvmKit.Chain) {
        self.chain = chain
    }
    
    /// - Parameters:
    ///   - amount: 金额
    ///   - to: 跨链接收人 Address
    func transactionData(amount: BigUInt,
                         to: String) -> TransactionData {
        let input = Web3jUtils.getEth2safeTransactionInput(amount: amount, toAddressHex: to) ??  Data()
        let address = try! EvmKit.Address(hex: getContractAddress(chain: chain))
        return TransactionData(to: address, value: BigUInt.zero, input: input)
    }
    
    // safe to wsafe
    func transactionDataSafe4(amount: BigUInt,
                         to: String) -> TransactionData {
        let toAddress = try! EvmKit.Address(hex: getSafe4ContractAddress(chain: chain))
        return TransactionData(to: toAddress, value: amount, input: to.hs.data)
    }

    /**
     * 获取跨链区块合约地址
     */
    func getContractAddress(chain: EvmKit.Chain) throws -> String {

        switch chain {
            case .ethereum: return "0xee9c1ea4dcf0aaf4ff2d78b6ff83aa69797b65eb"
            case .binanceSmartChain: return "0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1" //BSC正式环境
            case .polygon: return "0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779"
            default: throw WSafeKit.UnsupportedChainError.noWethAddress
        }
    }
    
    func getSafe4ContractAddress(chain: EvmKit.Chain) throws -> String {
        switch chain {
            case .ethereum: return "0x30728eBa408684D167CF59828261Db8A2A59E8C7"
            case .binanceSmartChain: return "0x471B9eB32a6750b0356E0C80294Ee035C4bdF60B" //BSC正式环境
            case .polygon: return "0x960Bb626aba915c242301EC47948Ba475CDeC090"
            default: throw WSafeKit.UnsupportedChainError.noSafeAddress
        }
    }
    /**
     * 获取跨链safe地址
     */
    func getSafeAddress(chain: EvmKit.Chain) throws -> String {
        switch chain {
            case .ethereum: return "Xnr78kmFtZBWKypYeyDLaaQRLf2EoMSgMV"
//            case .ethereumRopsten: return "XiY8mw8XXxfkfrgAwgVUs7qQW7vGGFLByx" //eth测试环境
            case .binanceSmartChain: return "XdyjRkZpyDdPD3uJAUC3MzJSoCtEZincFf" //BSC正式环境
//            case .binanceSmartChain: return "Xm3DvW7ZpmCYtyhtPSu5iYQknpofseVxaF" //BSC测试环境
            case .polygon: return "XuPmDoaNb6rbNywefkTbESHXiYqNpYvaPU"
            default: throw WSafeKit.UnsupportedChainError.noSafeAddress
        }
    }

    /**
     * 获取跨链safe网络类型
     */
    func getSafeNetType(chain: EvmKit.Chain) throws -> String {
        switch chain {
            case .ethereum: return "mainnet4"
            case .ethereumRopsten: return "mainnet4"
            case .binanceSmartChain: return "mainnet4" //BSC正式环境
            case .polygon: return "mainnet4"
            case .SafeFour: return "mainnet4"
            case .SafeFourTestNet: return "testnet4"
        default: throw WSafeKit.UnsupportedChainError.noSafeNetType
        }
    }
}
