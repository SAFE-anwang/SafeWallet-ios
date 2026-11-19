import Foundation
import WalletConnectSign

class DappRequestPayload {
    let dAppName: String
    let data: Data

    init(dAppName: String, data: Data) {
        self.dAppName = dAppName
        self.data = data
    }

    var method: String {
        fatalError("Must be overridden by subclass")
    }
}

extension DappRequestPayload {
    enum ParsingError: Error {
        case cantParseRequest
        case badJSONRPCRequest
    }
}
