import Foundation
import Hodler

extension HodlerPlugin.LockTimeInterval {
    static func title(lockTimeInterval: HodlerPlugin.LockTimeInterval?) -> String {
        guard let lockTimeInterval else {
            return "send.hodler_locktime_off".localized
        }

        switch lockTimeInterval {
        case .month: return "send.hodler_locktime_month".localized
        case .month_3: return "send.hodler_locktime_month_3".localized
        case .halfYear: return "send.hodler_locktime_half_year".localized
        case .month_9: return "send.hodler_locktime_month_9".localized
        case .year: return "send.hodler_locktime_year".localized
        case .year_3: return "send.hodler_locktime_year_3".localized
        case .year_5: return "send.hodler_locktime_year_5".localized
        case .year_10: return "send.hodler_locktime_year_10".localized
        }
    }
}
