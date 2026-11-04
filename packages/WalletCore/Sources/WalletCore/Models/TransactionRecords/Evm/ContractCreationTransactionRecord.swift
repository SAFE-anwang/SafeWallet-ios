import EvmKit
import MarketKit

class ContractCreationTransactionRecord: EvmTransactionRecord {
    let title: String?

    init(source: TransactionSource, transaction: Transaction, baseToken: Token, title: String? = nil, protected: Bool) {
        self.title = title
        super.init(source: source, transaction: transaction, baseToken: baseToken, ownTransaction: true, protected: protected)
    }
}
