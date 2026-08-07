import Combine
import EvmKit
import Foundation
import MarketKit
import TronKit

final class ChildWalletBridge {
    static let shared = ChildWalletBridge(activeStateStore: ChildWalletUserDefaultsActiveStateStore())

    private let storage: ChildWalletStore
    private let activeStateStore: ChildWalletActiveStateStore
    private let derivationService: ChildWalletDerivationService
    private let activeChildWalletChangedSubject = PassthroughSubject<ActiveChildWalletChange, Never>()

    init(
        storage: ChildWalletStore = ChildWalletFileStorage.defaultStorage(),
        activeStateStore: ChildWalletActiveStateStore = ChildWalletInMemoryActiveStateStore(),
        derivationService: ChildWalletDerivationService = ChildWalletDerivationService()
    ) {
        self.storage = storage
        self.activeStateStore = activeStateStore
        self.derivationService = derivationService
    }

    private func supportsChildWallet(account: Account) -> Bool {
        if case .mnemonic = account.type {
            return account.type.mnemonicSeed != nil
        }

        return false
    }

    private func supportsChildWallet(blockchainType: BlockchainType) -> Bool {
        blockchainType.isEvm || blockchainType == .tron || blockchainType == .safe4
    }

    private var defaultChildWalletBlockchainTypes: [BlockchainType] {
        BlockchainType.supported.filter { supportsChildWallet(blockchainType: $0) }
    }

    private var autoSeededDefaultTokenQueryIds: Set<String> {
        Set(defaultChildWalletBlockchainTypes.map { $0.defaultTokenQuery.id.lowercased() })
    }

    private func supportsChildWallet(enabledWallet: EnabledWallet) -> Bool {
        guard let tokenQuery = TokenQuery(id: enabledWallet.tokenQueryId) else {
            return false
        }

        return supportsChildWallet(blockchainType: tokenQuery.blockchainType)
    }

    private func supportsChildWallet(wallet: Wallet) -> Bool {
        supportsChildWallet(blockchainType: wallet.token.blockchainType)
    }

    private func activeChildWallet(account: Account) throws -> ChildWallet? {
        guard supportsChildWallet(account: account) else {
            return nil
        }

        if let activeChildWalletId = activeStateStore.activeChildWalletId(parentAccountId: account.id) {
            do {
                guard let childWallet = try storage.allChildWallets(parentAccountId: account.id)
                    .first(where: { $0.id == activeChildWalletId && !$0.isHidden })
                else {
                    clearActiveChildWallet(parentAccountId: account.id)
                    return nil
                }

                return childWallet
            } catch {
                throw ChildWalletError.storageUnavailable(error.smartDescription)
            }
        }

        guard let legacyActiveChildWallet = try? storage.activeChildWallet(parentAccountId: account.id) else {
            return nil
        }

        activeStateStore.setActiveChildWalletId(legacyActiveChildWallet.id, parentAccountId: account.id)
        return legacyActiveChildWallet
    }

    private func activeChildWalletId(parentAccountId: String, migrateLegacyStorage: Bool) -> String? {
        if let activeChildWalletId = activeStateStore.activeChildWalletId(parentAccountId: parentAccountId) {
            return activeChildWalletId
        }

        guard migrateLegacyStorage,
              let legacyActiveChildWalletId = try? storage.activeChildWallet(parentAccountId: parentAccountId)?.id
        else {
            return nil
        }

        activeStateStore.setActiveChildWalletId(legacyActiveChildWalletId, parentAccountId: parentAccountId)
        return legacyActiveChildWalletId
    }

    private func clearActiveChildWallet(parentAccountId: String) {
        activeStateStore.setActiveChildWalletId(nil, parentAccountId: parentAccountId)
        try? storage.setActiveChildWallet(parentAccountId: parentAccountId, childWalletId: nil)
    }

    private func cleanupLegacyAutoSeededEnabledWalletsIfNeeded(parentAccountId: String) throws {
        var parentState = try parentState(parentAccountId: parentAccountId)
        guard !parentState.legacyAutoSeededEnabledWalletsCleaned else {
            return
        }

        try storage.deleteAutoSeededEnabledWallets(
            tokenQueryIds: autoSeededDefaultTokenQueryIds,
            parentAccountId: parentAccountId
        )
        parentState.recordLegacyAutoSeededEnabledWalletsCleaned()
        try storage.save(parentState: parentState)
    }

    private func fileSafeWalletIdComponent(_ value: String) -> String {
        let data = Data(value.utf8)
        guard !data.isEmpty else {
            return "00"
        }

        return data.map { String(format: "%02x", $0) }.joined()
    }

    private func walletId(parentAccountId: String, derivationIndex: Int, blockchainType: BlockchainType) -> String {
        [
            "cw",
            "p\(fileSafeWalletIdComponent(parentAccountId))",
            "i\(derivationIndex)",
            "c\(fileSafeWalletIdComponent(blockchainType.uid))",
        ].joined(separator: "-")
    }
}

extension ChildWalletBridge {
    struct ActiveChildWalletChange: Equatable {
        let parentAccountId: String
        let childWalletId: String?
    }

    var activeChildWalletChangedPublisher: AnyPublisher<ActiveChildWalletChange, Never> {
        activeChildWalletChangedSubject.eraseToAnyPublisher()
    }
}

extension ChildWalletBridge {
    func isChildWalletActive(account: Account) -> Bool {
        guard supportsChildWallet(account: account) else {
            return false
        }

        return activeChildWalletId(account: account) != nil
    }

    func tokenManagementBlockchainTypes(account: Account) -> [BlockchainType]? {
        guard isChildWalletActive(account: account) else {
            return nil
        }

        return BlockchainType.supported.filter { supportsChildWallet(blockchainType: $0) }
    }

    func supportsTokenManagement(account: Account, blockchainType: BlockchainType) -> Bool {
        guard isChildWalletActive(account: account) else {
            return true
        }

        return supportsChildWallet(blockchainType: blockchainType)
    }

    func supports(account: Account?, token: Token) -> Bool {
        guard let account else {
            return true
        }

        return supportsTokenManagement(account: account, blockchainType: token.blockchainType)
    }

    func supports(account: Account?, blockchainType: BlockchainType) -> Bool {
        guard let account else {
            return true
        }

        return supportsTokenManagement(account: account, blockchainType: blockchainType)
    }

    func supports(account: Account?, sendData: SendData) -> Bool {
        guard let account, isChildWalletActive(account: account) else {
            return true
        }

        switch sendData {
        case let .evm(blockchainType, _, token):
            return supports(account: account, blockchainType: blockchainType) && supports(account: account, token: token)
        case let .tron(token, _):
            return supports(account: account, token: token)
        case let .tronGasFree(token, _, _):
            return supports(account: account, token: token)
        case let .swap(tokenIn, tokenOut, _, _, _):
            return supports(account: account, token: tokenIn) && supports(account: account, token: tokenOut)
        case let .liquidityAdd(token0, token1, _, _, _, _, _):
            return supports(account: account, token: token0) && supports(account: account, token: token1)
        case let .walletConnect(request):
            guard let chainId = Int(request.chain.id),
                  let blockchain = Core.shared.evmBlockchainManager.blockchain(chainId: chainId)
            else {
                return false
            }

            return supports(account: account, blockchainType: blockchain.type)
        case let .openCryptoPay(_, _, inner):
            return supports(account: account, sendData: inner)
        case let .evmSafe4TimeLock(blockchainType, _, _):
            return supports(account: account, blockchainType: blockchainType)
        case let .crossChain(baseWallet, _):
            return supports(account: account, token: baseWallet.token)
        case .bitcoin, .zcash, .zcashResend, .zcashShield, .ton, .stellar, .solana, .monero, .zano, .zanoAsset, .tonConnect:
            return false
        }
    }

    func identity(account: Account) -> ChildWalletIdentity {
        ChildWalletIdentity(account: account, childWallet: try? activeChildWallet(account: account))
    }

    func activeChildWalletId(parentAccountId: String) -> String? {
        activeChildWalletId(parentAccountId: parentAccountId, migrateLegacyStorage: true)
    }

    func activeChildWalletId(account: Account) -> String? {
        guard supportsChildWallet(account: account) else {
            return nil
        }

        if let activeChildWalletId = activeStateStore.activeChildWalletId(parentAccountId: account.id) {
            do {
                guard try activeChildWallet(account: account) != nil else {
                    return nil
                }
            } catch {
                return activeChildWalletId
            }

            return activeChildWalletId
        }

        return activeChildWalletId(parentAccountId: account.id, migrateLegacyStorage: true)
    }

    func displayName(account: Account) -> String {
        guard let childWallet = try? activeChildWallet(account: account) else {
            return account.name
        }

        return "\(account.name)（\(childWallet.name)）"
    }

    func contextAccountId(account: Account) -> String {
        guard let childWalletId = activeChildWalletId(account: account) else {
            return account.id
        }

        return [account.id, "child", childWalletId].joined(separator: ":")
    }

    func kitCacheKey(account: Account, blockchainType: BlockchainType) throws -> ChildWalletKitCacheKey {
        ChildWalletKitCacheKey(
            accountId: account.id,
            childWalletId: try activeChildWallet(account: account)?.id,
            blockchainType: blockchainType
        )
    }

    func walletId(account: Account, blockchainType: BlockchainType) throws -> String {
        guard let childWallet = try activeChildWallet(account: account) else {
            return account.id
        }

        return walletId(parentAccountId: account.id, derivationIndex: childWallet.derivationIndex, blockchainType: blockchainType)
    }

    func evmAddress(account: Account, blockchainType: BlockchainType) throws -> EvmKit.Address? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        guard supportsChildWallet(blockchainType: blockchainType) else {
            throw ChildWalletError.childWalletUnsupported("Blockchain \(blockchainType.uid) is not supported by child wallets.")
        }

        let chain = try Core.shared.evmBlockchainManager.chain(blockchainType: blockchainType)
        return try derivationService.evmAddress(account: account, childWallet: childWallet, chain: chain)
    }

    func evmAddress(account: Account, blockchainType: BlockchainType, chain: Chain) throws -> EvmKit.Address? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        guard supportsChildWallet(blockchainType: blockchainType) else {
            throw ChildWalletError.childWalletUnsupported("Blockchain \(blockchainType.uid) is not supported by child wallets.")
        }

        return try derivationService.evmAddress(account: account, childWallet: childWallet, chain: chain)
    }

    func evmSigner(account: Account, chain: Chain) throws -> EvmKit.Signer? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        return try derivationService.evmSigner(account: account, childWallet: childWallet, chain: chain)
    }

    func activeSafe4EvmKitWrapper() -> EvmKitWrapper? {
        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }

        return try? safe4EvmKitWrapper(account: account)
    }

    func activeEvmKitWrapper(blockchainType: BlockchainType) -> EvmKitWrapper? {
        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }

        return try? Core.shared.evmBlockchainManager
            .evmKitManager(blockchainType: blockchainType)
            .evmKitWrapper(account: account, blockchainType: blockchainType)
    }

    func activeTronKitWrapper() -> TronKitWrapper? {
        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }

        return try? Core.shared.tronAccountManager.tronKitManager.tronKitWrapper(account: account)
    }

    func safe4EvmKitWrapper(account: Account) throws -> EvmKitWrapper {
        try Core.shared.evmBlockchainManager
            .evmKitManager(blockchainType: .safe4)
            .evmKitWrapper(account: account, blockchainType: .safe4)
    }

    func tronAddress(account: Account) throws -> TronKit.Address? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        return try derivationService.tronAddress(account: account, childWallet: childWallet)
    }

    func tronSigner(account: Account) throws -> TronKit.Signer? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        return try derivationService.tronSigner(account: account, childWallet: childWallet)
    }

    func activeWallets(account: Account, walletStorage: WalletStorage) throws -> [Wallet]? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        let enabledWallets = try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: account.id)
        return try walletStorage.wallets(account: account, enabledWallets: enabledWallets)
    }

    func saveAndReturnUnhandled(enabledWallets: [EnabledWallet], account: Account) throws -> [EnabledWallet]? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        guard !enabledWallets.isEmpty else {
            return []
        }

        let supportedEnabledWallets = enabledWallets.filter { supportsChildWallet(enabledWallet: $0) }
        let unsupportedEnabledWallets = enabledWallets.filter { !supportsChildWallet(enabledWallet: $0) }

        if !supportedEnabledWallets.isEmpty {
            try storage.save(
                enabledWallets: supportedEnabledWallets,
                childWalletId: childWallet.id,
                parentAccountId: account.id
            )
        }

        return unsupportedEnabledWallets
    }

    func handleAndReturnUnhandled(newWallets: [Wallet], deletedWallets: [Wallet], account: Account) throws -> (newWallets: [Wallet], deletedWallets: [Wallet])? {
        guard let childWallet = try activeChildWallet(account: account) else {
            return nil
        }

        guard !(newWallets + deletedWallets).isEmpty else {
            return ([], [])
        }

        let supportedNewWallets = newWallets.filter { supportsChildWallet(wallet: $0) }
        let unsupportedNewWallets = newWallets.filter { !supportsChildWallet(wallet: $0) }
        let supportedDeletedWallets = deletedWallets.filter { supportsChildWallet(wallet: $0) }
        let unsupportedDeletedWallets = deletedWallets.filter { !supportsChildWallet(wallet: $0) }

        let enabledWallets = supportedNewWallets
            .map { ChildEnabledWallet(parentAccountId: account.id, childWalletId: childWallet.id, wallet: $0).enabledWallet(accountId: account.id) }
        if !enabledWallets.isEmpty {
            try storage.save(enabledWallets: enabledWallets, childWalletId: childWallet.id, parentAccountId: account.id)
        }

        let deletedTokenQueryIds = supportedDeletedWallets.map { $0.token.tokenQuery.id }
        if !deletedTokenQueryIds.isEmpty {
            try storage.delete(tokenQueryIds: deletedTokenQueryIds, childWalletId: childWallet.id, parentAccountId: account.id)
        }

        return (unsupportedNewWallets, unsupportedDeletedWallets)
    }

    func wallets(childWalletId: String, account: Account, marketKit: MarketKit.Kit) throws -> [Wallet] {
        try cleanupLegacyAutoSeededEnabledWalletsIfNeeded(parentAccountId: account.id)

        let enabledWallets = try storage.enabledWallets(childWalletId: childWalletId, parentAccountId: account.id)
            .filter { supportsChildWallet(enabledWallet: $0) }

        let queries = enabledWallets.compactMap { TokenQuery(id: $0.tokenQueryId) }
        let tokens = try marketKit.tokens(queries: queries)

        let blockchainUids = queries.map(\.blockchainType.uid)
        let blockchains = try marketKit.blockchains(uids: blockchainUids)

        return enabledWallets.compactMap { enabledWallet in
            guard let tokenQuery = TokenQuery(id: enabledWallet.tokenQueryId) else {
                return nil
            }

            if let token = tokens.first(where: { $0.tokenQuery == tokenQuery }) {
                return Wallet(token: token, account: account)
            }

            if let coinName = enabledWallet.coinName,
               let coinCode = enabledWallet.coinCode,
               let tokenDecimals = enabledWallet.tokenDecimals,
               let blockchain = blockchains.first(where: { $0.uid == tokenQuery.blockchainType.uid })
            {
                let token = Token(
                    coin: Coin(uid: tokenQuery.customCoinUid, name: coinName, code: coinCode, image: enabledWallet.coinImage),
                    blockchain: blockchain,
                    type: tokenQuery.tokenType,
                    decimals: tokenDecimals
                )

                return Wallet(token: token, account: account)
            }

            return nil
        }
    }

    func save(enabledWallets: [ChildEnabledWallet], parentAccountId: String) throws {
        for (childWalletId, childEnabledWallets) in Dictionary(grouping: enabledWallets, by: \.childWalletId) {
            let legacyEnabledWallets = childEnabledWallets
                .map { $0.enabledWallet(accountId: parentAccountId) }
                .filter { supportsChildWallet(enabledWallet: $0) }
            try storage.save(enabledWallets: legacyEnabledWallets, childWalletId: childWalletId, parentAccountId: parentAccountId)
        }
    }

    func childWallets(parentAccountId: String) throws -> [ChildWallet] {
        try storage.childWallets(parentAccountId: parentAccountId)
    }

    func allChildWallets(parentAccountId: String) throws -> [ChildWallet] {
        try storage.allChildWallets(parentAccountId: parentAccountId)
    }

    func kitWalletIdsToKeep(parentAccounts: [Account]) -> [String] {
        parentAccounts.flatMap { account -> [String] in
            guard supportsChildWallet(account: account),
                  let childWallets = try? storage.allChildWallets(parentAccountId: account.id)
            else {
                return []
            }

            return childWallets.flatMap { childWallet in
                defaultChildWalletBlockchainTypes.map {
                    walletId(parentAccountId: account.id, derivationIndex: childWallet.derivationIndex, blockchainType: $0)
                }
            }
        }
    }

    func createNextChildWallet(parentAccountId: String, name: String? = nil) throws -> ChildWallet {
        guard let derivationIndex = try nextDerivationIndex(parentAccountId: parentAccountId) else {
            throw ChildWalletError.invalidDerivationIndex
        }

        let childWallet = try ChildWallet(
            parentAccountId: parentAccountId,
            derivationIndex: derivationIndex,
            name: name ?? "子钱包 \(derivationIndex)",
            creationSource: .userCreated
        )
        try storage.save(childWallet: childWallet)
        try recordAllocated(parentAccountId: parentAccountId, derivationIndex: derivationIndex)
        return childWallet
    }

    func renameChildWallet(parentAccountId: String, childWalletId: String, name: String) throws -> ChildWallet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ChildWalletError.invalidName
        }

        guard var childWallet = try storage.allChildWallets(parentAccountId: parentAccountId).first(where: { $0.id == childWalletId }) else {
            throw ChildWalletError.childWalletNotFound
        }

        childWallet.name = trimmedName
        try storage.save(childWallet: childWallet)
        return childWallet
    }

    func hideChildWallet(parentAccountId: String, childWalletId: String) throws {
        guard var childWallet = try storage.allChildWallets(parentAccountId: parentAccountId).first(where: { $0.id == childWalletId }) else {
            throw ChildWalletError.childWalletNotFound
        }

        childWallet.isHidden = true
        try storage.save(childWallet: childWallet)

        if activeStateStore.activeChildWalletId(parentAccountId: parentAccountId) == childWalletId {
            try setActiveChildWallet(parentAccountId: parentAccountId, childWalletId: nil)
        }
    }

    func setActiveChildWallet(parentAccountId: String, childWalletId: String?) throws {
        if let childWalletId {
            try cleanupLegacyAutoSeededEnabledWalletsIfNeeded(parentAccountId: parentAccountId)
            try storage.setActiveChildWallet(parentAccountId: parentAccountId, childWalletId: childWalletId)
            activeStateStore.setActiveChildWalletId(childWalletId, parentAccountId: parentAccountId)
        } else {
            clearActiveChildWallet(parentAccountId: parentAccountId)
        }

        activeChildWalletChangedSubject.send(ActiveChildWalletChange(parentAccountId: parentAccountId, childWalletId: childWalletId))
    }

    func parentState(parentAccountId: String) throws -> ChildWalletParentState {
        try storage.parentState(parentAccountId: parentAccountId) ?? ChildWalletParentState.fresh(parentAccountId: parentAccountId)
    }

    func save(parentState: ChildWalletParentState) throws {
        try storage.save(parentState: parentState)
    }

    func recordAllocated(parentAccountId: String, derivationIndex: Int) throws {
        var state = try parentState(parentAccountId: parentAccountId)
        state.recordAllocated(index: derivationIndex)
        try storage.save(parentState: state)
    }

    func delete(parentAccountId: String) throws {
        activeStateStore.delete(parentAccountId: parentAccountId)
        try storage.delete(parentAccountId: parentAccountId)
    }

    func nextDerivationIndex(parentAccountId: String) throws -> Int? {
        let localMaxIndex = try storage.allChildWallets(parentAccountId: parentAccountId).map(\.derivationIndex).max() ?? 0
        let parentState = try parentState(parentAccountId: parentAccountId)
        let nextIndex = max(localMaxIndex, parentState.highestKnownIndex) + 1

        return ChildWallet.isValid(derivationIndex: nextIndex) ? nextIndex : nil
    }
}
