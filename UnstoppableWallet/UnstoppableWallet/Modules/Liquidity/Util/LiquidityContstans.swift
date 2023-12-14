import Foundation
import BigInt

class Constants {

    static let NULL_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    class DexFee {
        static let PANCAKE_SWAP = "0.0025"
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




