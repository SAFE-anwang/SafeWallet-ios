import Foundation

enum ListState: Equatable {
    case loading
    case items
    case error(NSError)

    static func == (lhs: ListState, rhs: ListState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.items, .items):
            return true
        case let (.error(lhsError), .error(rhsError)):
            return lhsError.domain == rhsError.domain && lhsError.code == rhsError.code
        default:
            return false
        }
    }
}
