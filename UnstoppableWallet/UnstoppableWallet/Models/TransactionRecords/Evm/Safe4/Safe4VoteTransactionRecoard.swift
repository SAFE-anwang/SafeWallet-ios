import EvmKit
import Foundation
import MarketKit

class Safe4VoteTransactionRecoard: EvmTransactionRecord {
    let from: String
    let to: String
    let value: TransactionValue

    init(source: TransactionSource, transaction: Transaction, baseToken: Token, from: String, to: String, value: TransactionValue) {
        self.from = from
        self.to = to
        self.value = value

        super.init(source: source, transaction: transaction, baseToken: baseToken, ownTransaction: false)
    }

    override var mainValue: TransactionValue? {
        value
    }
}

class Safe4NodeRegisterTransactionRecoard: EvmTransactionRecord {
    let method: String?
    let from: String
    let to: String
    let value: TransactionValue
    let contractAddress: String
    
    init(source: TransactionSource, transaction: Transaction, baseToken: Token,  method: String?, from: String, to: String, value: TransactionValue, contractAddress: String) {
        self.method = method
        self.from = from
        self.to = to
        self.value = value
        self.contractAddress = contractAddress
        
        super.init(source: source, transaction: transaction, baseToken: baseToken, ownTransaction: false)
    }

    override var mainValue: TransactionValue? {
        value
    }
}
