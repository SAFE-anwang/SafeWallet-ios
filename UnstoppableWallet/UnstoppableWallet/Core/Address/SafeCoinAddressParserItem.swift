import Foundation
import MarketKit
import RxSwift

class SafeCoinAddressParserItem {
    private let adapter: ISendSafeCoinAdapter

    init(adapter: ISendSafeCoinAdapter) {
        self.adapter = adapter
    }

}

extension SafeCoinAddressParserItem: IAddressParserItem {
    
    var blockchainType: BlockchainType { .safe }
    
    func handle(address: String) -> Single<Address> {
        do {
            try adapter.validateSafe(address: address)
            return Single.just(Address(raw: address, domain: nil))
        } catch {
            return Single.error(error)
        }
    }

    func isValid(address: String) -> Single<Bool> {
        do {
            try adapter.validateSafe(address: address)
            return Single.just(true)
        } catch {
            return Single.just(false)
        }
    }

}
