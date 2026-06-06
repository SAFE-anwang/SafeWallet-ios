import Foundation
import MarketKit

struct ManageWalletsTokenSorter {
    private func blockchainPriority(_ token: Token) -> Int {
        switch token.blockchainType {
        case .safe4: return 0
        case .safe: return 1
        default: return 2
        }
    }

    private func compareByFilter(_ lhs: Token, _ rhs: Token, filter: String) -> Bool? {
        let lhsExactCode = lhs.coin.code.lowercased() == filter
        let rhsExactCode = rhs.coin.code.lowercased() == filter

        if lhsExactCode != rhsExactCode {
            return lhsExactCode
        }

        let lhsStartsWithCode = lhs.coin.code.lowercased().hasPrefix(filter)
        let rhsStartsWithCode = rhs.coin.code.lowercased().hasPrefix(filter)

        if lhsStartsWithCode != rhsStartsWithCode {
            return lhsStartsWithCode
        }

        let lhsStartsWithName = lhs.coin.name.lowercased().hasPrefix(filter)
        let rhsStartsWithName = rhs.coin.name.lowercased().hasPrefix(filter)

        if lhsStartsWithName != rhsStartsWithName {
            return lhsStartsWithName
        }

        return nil
    }
}

extension ManageWalletsTokenSorter {
    func sorted(_ tokens: [Token], filter: String, preferredTokens: [Token]) -> [Token] {
        let lowercasedFilter = filter.lowercased()

        return tokens.sorted { lhs, rhs in
            if lowercasedFilter.isEmpty {
                let lhsEnabled = preferredTokens.contains(lhs)
                let rhsEnabled = preferredTokens.contains(rhs)

                if lhsEnabled != rhsEnabled {
                    return lhsEnabled
                }

                let lhsPriority = blockchainPriority(lhs)
                let rhsPriority = blockchainPriority(rhs)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
            }

            if !lowercasedFilter.isEmpty {
                if let result = compareByFilter(lhs, rhs, filter: lowercasedFilter) {
                    return result
                }
            }

            let lhsEnabled = preferredTokens.contains(lhs)
            let rhsEnabled = preferredTokens.contains(rhs)

            if lhsEnabled != rhsEnabled {
                return lhsEnabled
            }

            if lhs.blockchainType.order != rhs.blockchainType.order {
                return lhs.blockchainType.order < rhs.blockchainType.order
            }

            return (lhs.badge ?? "") < (rhs.badge ?? "")
        }
    }
}
