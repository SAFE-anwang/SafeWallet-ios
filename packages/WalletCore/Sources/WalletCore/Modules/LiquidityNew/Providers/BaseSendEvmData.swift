import EvmKit
import Foundation
import MarketKit

class BaseSendEvmData {
    let gasPrice: GasPrice?
    let evmFeeData: EvmFeeData?
    let nonce: Int?

    init(gasPrice: GasPrice?, evmFeeData: EvmFeeData?, nonce: Int?) {
        self.gasPrice = gasPrice
        self.evmFeeData = evmFeeData
        self.nonce = nonce
    }

    func feeFields(feeToken: Token, currency: Currency, feeTokenRate: Decimal?) -> [SendField] {
        EvmSendHelper.feeFields(evmFeeData: evmFeeData, gasPrice: gasPrice, feeToken: feeToken, currency: currency, feeTokenRate: feeTokenRate)
    }
}
