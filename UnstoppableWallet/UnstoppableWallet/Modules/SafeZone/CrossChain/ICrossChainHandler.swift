import Foundation
import EvmKit
import MarketKit

protocol ICrossChainHandler {
    var wallet: Wallet { get }
    var receiverBlockchainType: BlockchainType { get }
    var crossChainContract: String { get }
    var navTitle: String { get }
    func sendData(amount: Decimal, address: String) -> SendDataResult
}
