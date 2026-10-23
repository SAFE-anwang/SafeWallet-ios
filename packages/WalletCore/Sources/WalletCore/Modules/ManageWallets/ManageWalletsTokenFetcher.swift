import EvmKit
import Foundation
import MarketKit

struct ManageWalletsTokenFetcher {
    private let marketKit = Core.shared.marketKit
    private let safe4CustomTokenStorage = Core.shared.safe4CustomTokenStorage

    private var safe4Blockchain: Blockchain? {
        guard let blockchains = try? marketKit.blockchains(uids: [BlockchainType.safe4.uid]) else {
            return nil
        }

        return blockchains.first
    }

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

    private func safe4CustomTokens(account: Account, ownerAddress: String?, filter: String? = nil, allowedBlockchainTypes: [BlockchainType]?) -> [Token] {
        let lowercasedFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let safe4Blockchain else {
            return []
        }

        var tokens = [Token]()

        for tokenInfo in safe4CustomTokenStorage.allTokens(chainId: Safe4Network.currentChainId) {
            guard tokenInfo.isEligible(forOwner: ownerAddress) else {
                continue
            }

            if let lowercasedFilter, !lowercasedFilter.isEmpty {
                let matches = tokenInfo.address.lowercased().contains(lowercasedFilter)
                    || tokenInfo.symbol.lowercased().contains(lowercasedFilter)
                    || tokenInfo.name.lowercased().contains(lowercasedFilter)

                guard matches else {
                    continue
                }
            }

            let token = Token(
                coin: Coin(
                    uid: TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address)).customCoinUid,
                    name: tokenInfo.name,
                    code: tokenInfo.symbol,
                    image: tokenInfo.logoURI
                ),
                blockchain: safe4Blockchain,
                type: .eip20(address: tokenInfo.address),
                decimals: tokenInfo.decimals
            )

            guard account.type.supports(token: token) else {
                continue
            }

            if let allowedBlockchainTypes, !allowedBlockchainTypes.contains(token.blockchainType) {
                continue
            }

            tokens.append(token)
        }

        return tokens
    }

    private func safe4OwnerAddress(account: Account) -> String? {
        guard let chain = Core.shared.evmBlockchainManager.chain(chainId: Safe4Network.currentChainId) else {
            return nil
        }

        let bridge = ChildWalletBridge.shared
        let identity = bridge.identity(account: account)
        if identity.childWallet != nil {
            do {
                guard let address = try bridge.evmAddress(identity: identity, chain: chain) else {
                    return nil
                }
                return address.eip55
            } catch {
                return nil
            }
        }

        return try? AccountAddress.evmAddress(account: account, blockchainType: .safe4).eip55
    }

    private func safe4TokenIsEligible(_ token: Token, ownerAddress: String?, enabledTokenIds: Set<String>) -> Bool {
        guard token.blockchainType == .safe4,
              case let .eip20(address) = token.type
        else {
            return true
        }

        // Keep already-enabled wallets visible so users can still turn them off after
        // a token is demoted or disappears from the current catalog.
        if enabledTokenIds.contains(token.tokenQuery.id.lowercased()) {
            return true
        }

        guard let record = try? safe4CustomTokenStorage.asset(address: address, chainId: Safe4Network.currentChainId) else {
            return false
        }
        return record.isEligible(forOwner: ownerAddress)
    }

    private func filterPreferredTokens(_ tokens: [Token], filter: String, allowedBlockchainTypes: [BlockchainType]?) -> [Token] {
        let normalizedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tokens.filter { token in
            guard allowedBlockchainTypes?.contains(token.blockchainType) ?? true else {
                return false
            }
            guard !normalizedFilter.isEmpty else {
                return true
            }

            let reference: String?
            switch token.type {
            case let .eip20(address), let .spl(address), let .jetton(address):
                reference = address
            case let .stellar(_, issuer):
                reference = issuer
            case let .zanoAsset(id):
                reference = id
            case let .thorChainAsset(denom):
                reference = denom
            default:
                reference = nil
            }

            return token.coin.name.lowercased().contains(normalizedFilter)
                || token.coin.code.lowercased().contains(normalizedFilter)
                || reference?.lowercased().contains(normalizedFilter) == true
        }
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
        let ownerAddress = safe4OwnerAddress(account: account)
        let preferred = filterPreferredTokens(preferredTokens, filter: trimmed, allowedBlockchainTypes: allowedBlockchainTypes)
        let enabledTokenIds = Set(preferredTokens.map { $0.tokenQuery.id.lowercased() })

        do {
            let tokens: [Token]

            if trimmed.isEmpty {
                let featured = try featuredTokens(account: account)
                let supported = featured.filter { account.type.supports(token: $0) }
                let safe4Tokens = safe4CustomTokens(account: account, ownerAddress: ownerAddress, allowedBlockchainTypes: allowedBlockchainTypes)
                tokens = (preferred + safe4Tokens + supported)
                    .filter {
                        guard let allowedBlockchainTypes else {
                            return true
                        }
                        return allowedBlockchainTypes.contains($0.blockchainType)
                    }
                    .removeDuplicates()
            } else if let evmAddress = try? EvmKit.Address(hex: trimmed) {
                let fetched = try tokensByAddress(evmAddress.hex)
                tokens = (preferred + safe4CustomTokens(account: account, ownerAddress: ownerAddress, filter: trimmed, allowedBlockchainTypes: allowedBlockchainTypes) + fetched)
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
                tokens = (preferred + safe4CustomTokens(account: account, ownerAddress: ownerAddress, filter: trimmed, allowedBlockchainTypes: allowedBlockchainTypes) + fetched)
                    .filter { account.type.supports(token: $0) }
                    .removeDuplicates()
            }

            return tokens.filter {
                safe4TokenIsEligible($0, ownerAddress: ownerAddress, enabledTokenIds: enabledTokenIds)
            }
        } catch {
            return []
        }
    }
}
