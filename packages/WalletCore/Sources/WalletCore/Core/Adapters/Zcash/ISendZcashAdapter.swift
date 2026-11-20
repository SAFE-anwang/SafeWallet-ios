import Foundation
import RxSwift
import ZODLSwiftWalletSDK

protocol ISendZcashAdapter {
    var availableBalance: Decimal { get }
    var areFundsSpendable: Bool { get }
    func validate(address: String, checkSendToSelf: Bool) throws -> ZcashAdapter.AddressType
    func sendProposal(amount: Decimal, address: Recipient, memo: Memo?) async throws -> Proposal
    func sendSingle(amount: Decimal, address: Recipient, memo: Memo?) -> Single<Void>
    func send(proposal: Proposal) async throws -> String?
    func recipient(from stringEncodedAddress: String) -> Recipient?
}
