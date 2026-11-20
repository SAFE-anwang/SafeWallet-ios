import BitcoinCore
import Foundation
import HsToolKit
import MarketKit
import RxSwift

protocol ISendSafeCoinAdapter {
    var blockchainType: BlockchainType { get }
    func availableBalanceSafe(feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData]) -> Decimal
    func maximumSendAmountSafe(pluginData: [UInt8: IBitcoinPluginData]) -> Decimal?
    func minimumSendAmountSafe(address: String?) -> Decimal
    func validateSafe(address: String) throws
    func unspentOutputs(filters: UtxoFilters) -> [UnspentOutputInfo]
    func convertFeeSafe(amount: Decimal, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData]) throws -> SendInfo
    func sendInfoSafe(amount: Decimal, feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData]) throws -> SendInfo
    // need set: lockedTimeInterval: HodlerPlugin.LockTimeInterval?, reverseHex: String?
    func sendSingle(params: SendParameters, logger: HsToolKit.Logger) -> Single<Void>

//    func sendSingle(amount: Decimal, address: String, memo: String?, feeRate: Int, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData], sortMode: TransactionDataSortMode, rbfEnabled: Bool, logger: HsToolKit.Logger, lockedTimeInterval: HodlerPlugin.LockTimeInterval?, reverseHex: String?) -> Single<Void>
}
