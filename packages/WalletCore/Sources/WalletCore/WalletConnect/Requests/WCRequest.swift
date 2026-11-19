import Foundation

public struct WCRequest {
    let payload: WCRequestPayload
    let verdict: WCVerificationVerdict
    let dAppName: String
    var dAppUrl: String?
    var dAppIconUrl: String?

    var activeContextMatches: (() -> Bool)? = nil

    var isBlocked: Bool {
        if case .block = verdict { return true }
        return false
    }

    var isExpired: Bool { Self.isExpired(expiryTimestamp: payload.expiryTimestamp) }
    var expirationDate: Date? { payload.expiryTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    static func isExpired(expiryTimestamp: UInt64?, now: Date = Date()) -> Bool {
        guard let expiryTimestamp else { return false }
        return now.timeIntervalSince1970 >= TimeInterval(expiryTimestamp)
    }

    func checkExpiration() throws {
        guard activeContextMatches?() != false else { throw RequestError.accountChanged }
        guard !isExpired else { throw RequestError.expired }
    }

    enum RequestError: LocalizedError {
        case expired
        case accountChanged

        var errorDescription: String? {
            switch self {
            case .expired: return "wallet_connect.button.expired".localized
            case .accountChanged: return "Wallet context changed. Reopen the request in its original wallet."
            }
        }
    }
}
