import Hodler

/// Safe4 time-lock choices shown by the SwiftUI send flow.
public enum SafeTimeLockOption: UInt16, CaseIterable {
    case none
    case month
    case month_3
    case halfYear
    case month_9
    case year
    case year_3
    case year_5
    case year_10

    var lockTimeInterval: HodlerPlugin.LockTimeInterval? {
        switch self {
        case .none: return nil
        case .month: return .month
        case .month_3: return .month_3
        case .halfYear: return .halfYear
        case .month_9: return .month_9
        case .year: return .year
        case .year_3: return .year_3
        case .year_5: return .year_5
        case .year_10: return .year_10
        }
    }

    var title: String {
        HodlerPlugin.LockTimeInterval.title(lockTimeInterval: lockTimeInterval)
    }

    var days: Int? {
        switch self {
        case .none: return nil
        case .month: return 30
        case .month_3: return 30 * 3
        case .halfYear: return 30 * 6
        case .month_9: return 30 * 9
        case .year: return 30 * 12
        case .year_3: return 30 * 12 * 3
        case .year_5: return 30 * 12 * 5
        case .year_10: return 30 * 12 * 10
        }
    }
}
