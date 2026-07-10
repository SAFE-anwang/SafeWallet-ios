import EvmKit
import Foundation
import MarketKit

class Safe4WithdrawTransactionRecord: EvmTransactionRecord {
    let from: String
    let value: AppValue

    init(source: TransactionSource, transaction: Transaction, baseToken: Token, from: String, value: AppValue, protected: Bool) {
        self.from = from
        self.value = value

        super.init(source: source, transaction: transaction, baseToken: baseToken, ownTransaction: false, protected: protected)
    }

    override var mainValue: AppValue? {
        value
    }
}
