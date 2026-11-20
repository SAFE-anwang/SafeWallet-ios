import Foundation

enum SendLineLockError: Error {
    case wrongAmount
    case invalidMonth
}

extension SendLineLockError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .wrongAmount: return "safe_lock.amount.unlock.error".localized
        case .invalidMonth: return "safe_lock.amount.error".localized("1-120")
        }
    }

}
