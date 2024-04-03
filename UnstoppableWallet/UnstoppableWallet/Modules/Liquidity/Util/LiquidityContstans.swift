import Foundation
import BigInt
import EvmKit

class Constants {

    static let NULL_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    class DexFee {
        static let PANCAKE_SWAP = "0.0025"
    }
            
    static func routerAddressString(chain: Chain) throws -> String {
        switch chain {
        case .ethereum: return "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
        case .binanceSmartChain: return "0x10ED43C718714eb63d5aA57B78B54704E256024E"
        case .polygon: return "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"
        case .avalanche: return "0x60aE616a2155Ee3d9A68541Ba4544862310933d4"
        default: throw UnsupportedChainError.noRouterAddress
        }
    }

    static func factoryAddressString(chain: Chain) throws -> String {
        switch chain {
        case .ethereum: return "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
        case .binanceSmartChain: return "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
        case .polygon: return "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32"
        case .avalanche: return "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10"
        default: throw UnsupportedChainError.noFactoryAddress
        }
    }

    static func initCodeHashString(chain: Chain) throws -> String {
        switch chain {
        case .ethereum: return "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
        case .binanceSmartChain: return "0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5"
        case .polygon: return "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
        case .avalanche: return "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
        default: throw UnsupportedChainError.noInitCodeHash
        }
    }
    

    static let deadLine: Int = 20 // 20 min

    static func getDeadLine() -> BigUInt {
        let txDeadLine = (UInt64(Date().timeIntervalSince1970) + UInt64(60 * Constants.deadLine))
        return BigUInt(integerLiteral: txDeadLine)
    }

    // user default slippage
    static let slippage = Decimal(0.005)
    
    public enum UnsupportedChainError: Error {
        case noRouterAddress
        case noFactoryAddress
        case noInitCodeHash
    }
}




