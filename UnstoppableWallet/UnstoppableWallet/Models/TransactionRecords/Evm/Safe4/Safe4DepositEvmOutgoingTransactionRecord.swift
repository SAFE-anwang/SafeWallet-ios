import EvmKit
import Foundation
import MarketKit

class Safe4DepositEvmOutgoingTransactionRecord: EvmTransactionRecord {
    
    let to: String
    let value: TransactionValue
    var sentToSelf: Bool

    init(source: TransactionSource, transaction: Transaction, baseToken: Token, to: String, value: TransactionValue, sentToSelf: Bool) {
        self.to = to
        self.value = value
        self.sentToSelf = sentToSelf

        super.init(source: source, transaction: transaction, baseToken: baseToken, ownTransaction: true)
    }

    override var mainValue: TransactionValue? {
        value
    }
}
extension Safe4DepositEvmOutgoingTransactionRecord {
    
    func sentToSelf(from: EvmKit.Address?, input: Data?) -> Bool {
       if let address = address(input: input) {
           return address == from
       }else {
           return false
       }
    }

}

func address(input: Data?) -> EvmKit.Address? {
   guard let input else { return nil }
   let parsedArguments = ContractMethodHelper.decodeABI(inputArguments: Data(input.suffix(from: 4)), argumentTypes: [EvmKit.Address.self])
   let owner = parsedArguments[0] as? EvmKit.Address
   return owner
}
