import Foundation

enum SendTransactionError: Error {
    case noFee
    case wrongAmount
    case invalidAddress
}

extension SendTransactionError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .wrongAmount: return "alert.wrong_amount".localized
        case .noFee: return "alert.no_fee".localized
        case .invalidAddress: return "invalid address"  // FIXME: localize or find the way to avoid this
        }
    }

}


enum SendLineLockError: Error {
    case wrongAmount
    case invalidMonth
}

extension SendLineLockError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .wrongAmount: return "safe_lock.amount.unlock.error".localized
        case .invalidMonth: return "safe_lock.amount.error".localized
        }
    }

}
