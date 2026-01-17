import Foundation
import EvmKit
import BigInt
import HsToolKit
import web3swift

class Web3jUtils {

    // safe4 swap
    static func getSafe4SwapSrcTransactionInput() -> Data? {
        let methodId = "0xd0e30db0".hs.hexData ?? Data()
        let data = ContractMethodHelper.encodedABI(methodId: methodId, arguments: [])
        return data
    }
    
    // safe4 swap
    static func getSrcSwapSafe4TransactionInput(amount: BigUInt) -> Data? {
        let methodId = "0x2e1a7d4d".hs.hexData ?? Data()
        let data = ContractMethodHelper.encodedABI(methodId: methodId, arguments: [amount])
        return data
    }
    
    // cross chain: wsafe to safe
    static func getEth2safeTransactionInput(amount: BigUInt,
                                            toAddressHex: String) -> Data? {
        let methodId = Safe4Methods.Eth2safe.id.hs.hexData ?? Data()
        let data = ContractMethodHelper.encodedABI(methodId: methodId, arguments: [amount, toAddressHex])
        return data
    }
    
    // cross chain to USDT-(SAFE4)
    static func send_USDT_ETH_TransactionInput(address: EvmKit.Address, amount: BigUInt) -> Data? {
        let methodId = "0xa9059cbb".hs.hexData ?? Data()
        let data = ContractMethodHelper.encodedABI(methodId: methodId, arguments: [address, amount])
        return data
    }
    // cross chain to USDT-(ETH,BSC,TRON,SOL)
    static func send_USDT_SAFE4_TransactionInput(amount: BigUInt, address: String, network: String) -> Data? {
        // crossChainRedeem( uint256 amount, string _network, string _to )
        let methodId = "0x49530e18".hs.hexData ?? Data()
        let data = ContractMethodHelper.encodedABI(methodId: methodId, arguments: [amount, network, address])
        return data
    }
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
