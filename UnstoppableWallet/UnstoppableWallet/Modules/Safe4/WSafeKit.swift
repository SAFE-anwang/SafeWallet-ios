import Foundation
import EvmKit
import BigInt
import web3swift
import Web3Core
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
        let input = Web3jUtils.getEth2safeTransactionInput(amount: amount, to: to) ??  Data()
        let address = try! EvmKit.Address(hex: getContractAddress(chain: chain))
        return TransactionData(to: address, value: BigUInt.zero, input: input)
    }

    /**
     * 获取跨链eth合约地址
     */
    func getContractAddress(chain: EvmKit.Chain) throws -> String {
        switch chain {
            case .ethereum: return "0xee9c1ea4dcf0aaf4ff2d78b6ff83aa69797b65eb"
//            case .ethereumRopsten: return "0x32885f2faf83aeee39e2cfe7f302e3bb884869f4" //eth测试环境
            case .binanceSmartChain: return "0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1" //BSC正式环境
//           case .binanceSmartChain: return "0xa3d8077c3a447049164e60294c892e5e4c7f3ad2" //BSC测试环境
            case .polygon: return "0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779"
        default: throw WSafeKit.UnsupportedChainError.noWethAddress
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
            case .ethereum: return "mainnet"
            case .ethereumRopsten: return "testnet"
            case .binanceSmartChain: return "mainnet" //BSC正式环境
            case .polygon: return "mainnet"
        default: throw WSafeKit.UnsupportedChainError.noSafeNetType
        }
    }
}

fileprivate class Web3jUtils {
    
    static func getEth2safeTransactionInput(amount: BigUInt,
                                            to: String) -> Data? {
        let methodIDHex = "0xbc157d0c" // => "eth2safe"
        
        let types: [ABI.Element.ParameterType] = [.uint(bits: 256),
                                                  .string]
        let values: [Any] = [amount, to]
        let parameterData = ABIEncoder.encode(types: types, values: values) ?? Data()
                
        return Data(hex: methodIDHex) + parameterData
    }
}
