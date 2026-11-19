import EvmKit
import Foundation

import BigInt

public class DappSignRequest: Identifiable {
    public let id: Int
    let chain: Chain
    let payload: DappRequestPayload

    init(id: Int, chain: Chain, payload: DappRequestPayload) {
        self.id = id
        self.chain = chain
        self.payload = payload
    }

    func convert(result _: Any) -> String? {
        nil
    }

    struct Chain {
        let id: String
        let chainName: String?
        let address: String?

        init(id: String, chainName: String? = nil, address: String? = nil) {
            self.id = id
            self.chainName = chainName
            self.address = address
        }

        var description: String {
            chainName ?? id
        }
    }
}

extension DappSignRequest {
    enum CreationError: Error {
        case noActiveAccount
        case invalidChain
        case cantCreateAddress
    }
}
