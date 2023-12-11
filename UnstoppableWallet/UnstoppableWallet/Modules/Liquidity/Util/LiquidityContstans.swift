import BigInt
import Foundation

class Constants {

    static let NULL_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    static let PERMIT_TYPEHASH = "0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9"

    class DexFee {
        static let PANCAKE_SWAP = "0.0025"
    }
    
    class Tokens {
        
        static let USDT = "0x55d398326f99059ff775485246999027b3197955"
        
        static let SAFE = "0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1"
        
        static let BTP = "0x40f75ed09c7bc89bf596ce0ff6fb2ff8d02ac019"
    }
    
    class DEX {

        static let PANCAKE_V2_ROUTER_ADDRESS = "0x10ed43c718714eb63d5aa57b78b54704e256024e"
        
        static let PANCAKE_V2_FACTORY_ADDRESS = "0xca143ce32fe78f1f7019d7d551a6402fc5350c73"
    }

    class INIT_CODE_HASH {
        
        static let PANCAKE_SWAP_FACTORY_INIT_CODE_HASH = "0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5"
        
    }

    static let deadLine: Int = 20 // 20 min

    static func getDeadLine() -> BigUInt {
        let txDeadLine = (UInt64(Date().timeIntervalSince1970) + UInt64(60 * Constants.deadLine))
        return BigUInt(integerLiteral: txDeadLine)
    }

    // user default slippage
    static let slippage = Decimal(0.005)
}




