import Foundation
import MarketKit
import HsCryptoKit
import BigInt
import HsExtensions
import EvmKit

struct LiquidityPair {
    
    let pairAddress: EvmKit.Address
    let item0: LiquidityPairItem
    let item1: LiquidityPairItem
    
    static func getPairAddress(evmKit: EvmKit.Kit, itemA: LiquidityPairItem, itemB: LiquidityPairItem) -> LiquidityPair? {
        let (item0, item1) = itemA.sortsBefore(item: itemB) ? (itemA, itemB) : (itemB, itemA)
        do {
            let factoryAddressString = try Constants.factoryAddressString(chain: evmKit.chain)
            let initCodeHashString = try Constants.initCodeHashString(chain: evmKit.chain)
            let pairAddress = generatePairAddress(address0: item0.address, address1: item1.address, factoryAddressString: factoryAddressString, initCodeHashString: initCodeHashString)
            return LiquidityPair(pairAddress: pairAddress, item0: item0, item1: item1)
        }catch {
            return nil
        }
    }
    
    private static func generatePairAddress(address0: EvmKit.Address, address1: EvmKit.Address, factoryAddressString: String, initCodeHashString: String) -> EvmKit.Address {
        let data = "ff".hs.hexData! +
                factoryAddressString.hs.hexData! +
                Crypto.sha3(address0.raw + address1.raw) +
                initCodeHashString.hs.hexData!

        return EvmKit.Address(raw: Crypto.sha3(data).suffix(20))
    }
}

struct LiquidityPairItem {
    let token: MarketKit.Token
    let address: EvmKit.Address
    
    func sortsBefore(item: LiquidityPairItem) -> Bool {
        self.address.raw.hs.hexString.lowercased() < item.address.raw.hs.hexString.lowercased()
    }
}
