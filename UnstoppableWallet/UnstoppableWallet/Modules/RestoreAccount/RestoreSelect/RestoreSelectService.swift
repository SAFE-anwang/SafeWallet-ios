import HdWalletKit
import MarketKit
import RxRelay
import RxSwift

class RestoreSelectService {
    private let accountName: String
    private let accountType: AccountType
    private let isManualBackedUp: Bool
    private let isFileBackedUp: Bool
    private let accountFactory: AccountFactory
    private let accountManager: AccountManager
    private let walletManager: WalletManager
    private let restoreStateManager: RestoreStateManager
    private let marketKit: MarketKit.Kit
    private let blockchainTokensService: BlockchainTokensService
    private let restoreSettingsService: RestoreSettingsService
    private let allowedBitcoinDerivations: Set<MnemonicDerivation>?
    private let allowedBlockchainTypes: Set<BlockchainType>?
    private let autoEnableDefaultTokensForAllowedBlockchains: Bool
    private let blockchainsRequireManualTokenSelection: Set<BlockchainType>?
    private let disposeBag = DisposeBag()

    private var tokens = [Token]()
    private(set) var enabledTokens = Set<Token>()

    private var restoreSettingsMap = [Token: RestoreSettings]()

    private let cancelEnableBlockchainRelay = PublishRelay<BlockchainType>()
    private let canRestoreRelay = BehaviorRelay<Bool>(value: false)

    private let itemsRelay = PublishRelay<[Item]>()
    var items: [Item] = [] {
        didSet {
            itemsRelay.accept(items)
        }
    }

    private let statPage: StatPage

    init(
        accountName: String,
        accountType: AccountType,
        statPage: StatPage,
        isManualBackedUp: Bool,
        isFileBackedUp: Bool,
        accountFactory: AccountFactory,
        accountManager: AccountManager,
        walletManager: WalletManager,
        restoreStateManager: RestoreStateManager,
        marketKit: MarketKit.Kit,
        blockchainTokensService: BlockchainTokensService,
        restoreSettingsService: RestoreSettingsService,
        allowedBitcoinDerivations: Set<MnemonicDerivation>? = nil,
        allowedBlockchainTypes: Set<BlockchainType>? = nil,
        autoEnableDefaultTokensForAllowedBlockchains: Bool = false,
        blockchainsRequireManualTokenSelection: Set<BlockchainType>? = nil
    ) {
        self.accountName = accountName
        self.accountType = accountType
        self.statPage = statPage
        self.isManualBackedUp = isManualBackedUp
        self.isFileBackedUp = isFileBackedUp
        self.accountFactory = accountFactory
        self.accountManager = accountManager
        self.walletManager = walletManager
        self.restoreStateManager = restoreStateManager
        self.marketKit = marketKit
        self.blockchainTokensService = blockchainTokensService
        self.restoreSettingsService = restoreSettingsService
        self.allowedBitcoinDerivations = allowedBitcoinDerivations
        self.allowedBlockchainTypes = allowedBlockchainTypes
        self.autoEnableDefaultTokensForAllowedBlockchains = autoEnableDefaultTokensForAllowedBlockchains
        self.blockchainsRequireManualTokenSelection = blockchainsRequireManualTokenSelection

        subscribe(disposeBag, blockchainTokensService.approveTokensObservable) { [weak self] blockchain, tokens in
            self?.handleApproveTokens(blockchain: blockchain, tokens: tokens)
        }
        subscribe(disposeBag, blockchainTokensService.rejectApproveTokensObservable) { [weak self] blockchain in
            self?.handleCancelEnable(blockchain: blockchain)
        }
        subscribe(disposeBag, restoreSettingsService.approveSettingsObservable) { [weak self] tokenWithSettings in
            self?.handleApproveRestoreSettings(token: tokenWithSettings.token, settings: tokenWithSettings.settings)
        }
        subscribe(disposeBag, restoreSettingsService.rejectApproveSettingsObservable) { [weak self] token in
            self?.handleCancelEnable(blockchain: token.blockchain)
        }

        syncInternalItems()
        autoEnableAllowedBlockchainsIfNeeded()
        syncState()
    }

    private func syncInternalItems() {
        do {
            let tokenQueries = BlockchainType.supported.map(\.nativeTokenQueries).flatMap { $0 }
            let allTokens = try marketKit.tokens(queries: tokenQueries)

            tokens = allTokens.filter { token in
                accountType.supports(token: token)
                    && supportsDerivationLimit(token: token)
                    && supportsBlockchainLimit(token: token)
            }
        } catch {
            // todo
        }
    }

    private func supportsBlockchainLimit(token: Token) -> Bool {
        guard let allowedBlockchainTypes else {
            return true
        }

        return allowedBlockchainTypes.contains(token.blockchainType)
    }

    private func autoEnableAllowedBlockchainsIfNeeded() {
        guard autoEnableDefaultTokensForAllowedBlockchains, let allowedBlockchainTypes else {
            return
        }

        for blockchainType in allowedBlockchainTypes {
            let blockchainTokens = tokens.filter { $0.blockchainType == blockchainType }
            guard let firstToken = blockchainTokens.first else {
                continue
            }

            let tokensToEnable: [Token]
            if blockchainTokens.count == 1 {
                tokensToEnable = [firstToken]
            } else {
                let defaults = blockchainTokens.filter(\.type.isDefault)
                tokensToEnable = defaults.isEmpty ? [firstToken] : defaults
            }

            handleApproveTokens(blockchain: firstToken.blockchain, tokens: tokensToEnable)
        }
    }

    private func supportsDerivationLimit(token: Token) -> Bool {
        guard let allowedBitcoinDerivations else {
            return true
        }

        guard token.blockchainType == .bitcoin || token.blockchainType == .litecoin else {
            return true
        }

        guard let derivation = token.type.derivation else {
            return true
        }

        return allowedBitcoinDerivations.contains(derivation)
    }

    private func isEnabled(blockchain: Blockchain) -> Bool {
        enabledTokens.contains { $0.blockchain == blockchain }
    }

    private func hasSettings(blockchain: Blockchain) -> Bool {
        tokens.filter { $0.blockchain == blockchain }.count > 1
    }

    private func item(blockchain: Blockchain) -> Item {
        let enabled = isEnabled(blockchain: blockchain)

        return Item(
            blockchain: blockchain,
            enabled: enabled,
            hasSettings: enabled && hasSettings(blockchain: blockchain)
        )
    }

    private func syncState() {
        let blockchains = Set(tokens.map(\.blockchain))
        items = blockchains.sorted { $0.type.order < $1.type.order }.map { item(blockchain: $0) }
    }

    private func syncCanRestore() {
        canRestoreRelay.accept(!enabledTokens.isEmpty)
    }

    private func handleApproveTokens(blockchain: Blockchain, tokens: [Token]) {
        let existingTokens = enabledTokens.filter { $0.blockchain == blockchain }

        let newTokens = tokens.filter { !existingTokens.contains($0) }
        let removedTokens = existingTokens.filter { !tokens.contains($0) }

        for token in newTokens {
            enabledTokens.insert(token)
        }

        for token in removedTokens {
            enabledTokens.remove(token)
        }

        syncCanRestore()
        syncState()
    }

    private func handleApproveRestoreSettings(token: Token, settings: RestoreSettings = [:]) {
        if !settings.isEmpty {
            restoreSettingsMap[token] = settings
        }

        enabledTokens.insert(token)

        syncCanRestore()
        syncState()
    }

    private func handleCancelEnable(blockchain: Blockchain) {
        if !isEnabled(blockchain: blockchain) {
            cancelEnableBlockchainRelay.accept(blockchain.type)
        }
    }
}

extension RestoreSelectService {
    var itemsObservable: Observable<[Item]> {
        itemsRelay.asObservable()
    }

    var cancelEnableBlockchainObservable: Observable<BlockchainType> {
        cancelEnableBlockchainRelay.asObservable()
    }

    var canRestoreObservable: Observable<Bool> {
        canRestoreRelay.asObservable()
    }

    func enable(blockchainUid: String) {
        let tokens = tokens.filter { $0.blockchain.uid == blockchainUid }

        guard let token = tokens.first else {
            return
        }

        let requireManualSelection = blockchainsRequireManualTokenSelection?.contains(token.blockchainType) ?? false

        if tokens.count == 1 {
            if !token.blockchainType.restoreSettingTypes.isEmpty {
                restoreSettingsService.approveSettings(token: token)
            } else {
                handleApproveTokens(blockchain: token.blockchain, tokens: [token])
            }
        } else {
            let enabledTokens = requireManualSelection ? [] : tokens.filter(\.type.isDefault)
            blockchainTokensService.approveTokens(blockchain: token.blockchain, tokens: tokens, enabledTokens: enabledTokens)
        }
    }

    func disable(blockchainUid: String) {
        enabledTokens = enabledTokens.filter { $0.blockchain.uid != blockchainUid }

        for token in restoreSettingsMap.keys {
            if token.blockchain.uid == blockchainUid {
                restoreSettingsMap.removeValue(forKey: token)
            }
        }

        syncState()
        syncCanRestore()
    }

    func configure(blockchainUid: String) {
        let tokens = tokens.filter { $0.blockchain.uid == blockchainUid }

        guard let token = tokens.first else {
            return
        }

        let enabledTokens = Array(enabledTokens.filter { $0.blockchain.uid == blockchainUid })
        blockchainTokensService.approveTokens(blockchain: token.blockchain, tokens: tokens, enabledTokens: enabledTokens, allowEmpty: true)
    }

    func restore() {
        let account = accountFactory.account(
            type: accountType,
            origin: .restored,
            backedUp: isManualBackedUp,
            fileBackedUp: isFileBackedUp,
            name: accountName
        )
        accountManager.save(account: account)

        for (token, settings) in restoreSettingsMap {
            restoreSettingsService.save(settings: settings, account: account, blockchainType: token.blockchainType)
        }

        guard !enabledTokens.isEmpty else {
            return
        }

        for blockchainType in Set(enabledTokens.map(\.blockchainType)) {
            restoreStateManager.setShouldRestore(account: account, blockchainType: blockchainType)
        }

        let wallets = enabledTokens.map { Wallet(token: $0, account: account) }
        walletManager.save(wallets: wallets)

        stat(page: statPage, event: .importWallet(walletType: accountType.statDescription))
    }
}

extension RestoreSelectService {
    struct Item {
        let blockchain: Blockchain
        let enabled: Bool
        let hasSettings: Bool
    }
}
