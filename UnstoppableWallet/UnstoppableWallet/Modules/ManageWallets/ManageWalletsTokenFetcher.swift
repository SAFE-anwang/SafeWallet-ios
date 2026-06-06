import EvmKit
import Foundation
import MarketKit

struct ManageWalletsTokenFetcher {
    private let marketKit = Core.shared.marketKit
    private let safe4CustomTokenStorage = Core.shared.safe4CustomTokenStorage

    private func tokenQueries(account: Account) -> [TokenQuery] {
        switch account.type {
        case .hdExtendedKey:
            return BtcBlockchainManager.blockchainTypes.flatMap(\.nativeTokenQueries)
        default:
            return BlockchainType.supported.map(\.defaultTokenQuery)
        }
    }

    private func normalizedAllowedBlockchainTypes(_ allowedBlockchainTypes: [BlockchainType]?) -> [BlockchainType]? {
        guard let allowedBlockchainTypes else {
            return nil
        }

        var result = allowedBlockchainTypes
        if allowedBlockchainTypes.contains(.safe4), !result.contains(.safe) {
            result.append(.safe)
        }

        return result.removeDuplicates()
    }

    private func safe4CustomTokens(account: Account, filter: String? = nil, allowedBlockchainTypes: [BlockchainType]?) -> [Token] {
        let lowercasedFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var tokens = [Token]()

        for tokenInfo in safe4CustomTokenStorage.allTokens() {
            if let lowercasedFilter, !lowercasedFilter.isEmpty {
                let matches = tokenInfo.address.lowercased().contains(lowercasedFilter)
                    || tokenInfo.symbol.lowercased().contains(lowercasedFilter)
                    || tokenInfo.name.lowercased().contains(lowercasedFilter)

                guard matches else {
                    continue
                }
            }

            let query = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address))

            guard let token = try? marketKit.token(query: query), account.type.supports(token: token) else {
                continue
            }

            if let allowedBlockchainTypes, !allowedBlockchainTypes.contains(token.blockchainType) {
                continue
            }

            tokens.append(token)
        }

        return tokens
    }

    private func featuredTokens(account: Account) throws -> [Token] {
        let queries = tokenQueries(account: account)
        return try marketKit.tokens(queries: queries)
    }

    private func tokensByAddress(_ address: String) throws -> [Token] {
        try marketKit.tokens(reference: address)
    }

    private func tokensBySearch(_ filter: String, allowedBlockchainTypes: [BlockchainType]? = nil) throws -> [Token] {
        let fullCoins = try marketKit.fullCoins(filter: filter, limit: 100, allowedBlockchainTypes: allowedBlockchainTypes)
        return fullCoins.flatMap(\.tokens)
    }
}

extension ManageWalletsTokenFetcher {
    func fetch(filter: String, account: Account, preferredTokens: [Token], allowedBlockchainTypes: [BlockchainType]? = nil) -> [Token] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        let allowedBlockchainTypes = normalizedAllowedBlockchainTypes(allowedBlockchainTypes)

        do {
            let tokens: [Token]

            if trimmed.isEmpty {
                let featured = try featuredTokens(account: account)
                let supported = featured.filter { account.type.supports(token: $0) }
                let safe4Tokens = safe4CustomTokens(account: account, allowedBlockchainTypes: allowedBlockchainTypes)
                tokens = (preferredTokens + supported + safe4Tokens)
                    .filter {
                        guard let allowedBlockchainTypes else {
                            return true
                        }
                        return allowedBlockchainTypes.contains($0.blockchainType)
                    }
                    .removeDuplicates()
            } else if let evmAddress = try? EvmKit.Address(hex: trimmed) {
                let fetched = try tokensByAddress(evmAddress.hex)
                tokens = (fetched + safe4CustomTokens(account: account, filter: trimmed, allowedBlockchainTypes: allowedBlockchainTypes))
                    .filter {
                        account.type.supports(token: $0)
                    }
                    .filter {
                        guard let allowedBlockchainTypes else {
                            return true
                        }
                        return allowedBlockchainTypes.contains($0.blockchainType)
                    }
                    .removeDuplicates()
            } else {
                let fetched = try tokensBySearch(trimmed, allowedBlockchainTypes: allowedBlockchainTypes)
                tokens = (fetched + safe4CustomTokens(account: account, filter: trimmed, allowedBlockchainTypes: allowedBlockchainTypes))
                    .filter { account.type.supports(token: $0) }
                    .removeDuplicates()
            }

            return tokens
        } catch {
            return []
        }
    }
}
