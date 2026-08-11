import Combine
import Foundation
import MarketKit

class ManageWalletsViewModel: ObservableObject {
    private let account: Account
    private let walletManager = Core.shared.walletManager
    private let childWalletBridge = ChildWalletBridge.shared
    private let restoreSettingsService: RestoreSettingsService

    private let tokenFetcher = ManageWalletsTokenFetcher()
    private let tokenInfoProvider: ManageWalletsTokenInfoProvider

    private var tokens = [Token]()
    private var wallets = Set<Wallet>()
    private let childWalletBlockchainTypes: [BlockchainType]?
    private var cancellables = Set<AnyCancellable>()

    @Published var items = [Item]()
    @Published var enabledTokens: [Int: Bool] = [:]

    @Published var filter = ""
    let canAddToken: Bool

    let blockchains: [Blockchain]
    @Published var blockchainFilter: Blockchain? = nil {
        didSet {
            guard blockchainFilter != oldValue else {
                return
            }

            reloadTokens()
        }
    }

    var emptySearchText: String {
        childWalletBlockchainTypes == nil ? "manage_wallets.not_found".localized : "当前子钱包仅支持 EVM/TRON/SAFE 资产。"
    }

    var childWalletNoticeText: String? {
        guard childWalletBlockchainTypes != nil else {
            return nil
        }

        return "当前为子钱包模式，仅显示并管理 EVM/TRON/SAFE 资产；其他链资产请切回主钱包查看。"
    }

    init(account: Account, restoreSettingsService: RestoreSettingsService) {
        self.account = account
        self.restoreSettingsService = restoreSettingsService
        let childWalletBlockchainTypes = ChildWalletBridge.shared.tokenManagementBlockchainTypes(account: account)
        self.childWalletBlockchainTypes = childWalletBlockchainTypes
        canAddToken = account.type.canAddTokens && !AddTokenModule.items(account: account).isEmpty
        tokenInfoProvider = ManageWalletsTokenInfoProvider(restoreSettingsService: restoreSettingsService)

        wallets = Set(walletManager.activeWallets)

        let supported = (try? Core.shared.marketKit.blockchains(uids: BlockchainType.supported.map(\.uid))) ?? []

        blockchains = supported
            .filter { $0.type != .safe }
            .filter { childWalletBlockchainTypes?.contains($0.type) ?? true }
            .sorted(by: { $0.type.order < $1.type.order })
        setupBindings()
        reloadTokens(initial: true)
    }

    private func setupBindings() {
        $filter
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.global(qos: .userInitiated))
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadTokens()
            }
            .store(in: &cancellables)

        walletManager.activeWalletDataUpdatedPublisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] walletData in
                self?.handleWalletsUpdated(walletData.wallets)
            }
            .store(in: &cancellables)

        restoreSettingsService.approveSettingsPublisher
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] tokenWithSettings in
                self?.handleApproveRestoreSettings(token: tokenWithSettings.token, settings: tokenWithSettings.settings)
            }
            .store(in: &cancellables)

        restoreSettingsService.rejectApproveSettingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadTokens()
            }
            .store(in: &cancellables)
    }

    private func reloadTokens(initial: Bool = false) {
        let enabledTokens = wallets
            .map(\.token)

        let fetched = tokenFetcher.fetch(
            filter: filter,
            account: account,
            preferredTokens: enabledTokens,
            allowedBlockchainTypes: allowedBlockchainTypes
        )

        let context = TokenSortContext()
        context.filter = filter
        context.enabledTokens = Set(enabledTokens)

        let criteria = filter.isEmpty
            ? SortCriterion.tokenByBlockchain
            : SortCriterion.tokenFilteredByBlockchain

        tokens = fetched.sorted(by: criteria, context: context)
        reloadItems(initial: initial)
    }

    private func reloadItems(initial: Bool = false) {
        var enabled: [Int: Bool] = [:]
        let items = tokens.map { token in
            let (item, isEnabled) = item(token: token)
            enabled[token.hashValue] = isEnabled

            return item
        }

        if initial {
            self.items = items
            enabledTokens = enabled
        } else {
            DispatchQueue.main.async {
                self.items = items
                self.enabledTokens = enabled
            }
        }
    }

    private func item(token: Token) -> (Item, Bool) {
        let isEnabled = wallets.contains { $0.token == token }

        return (
            Item(
                token: token,
                hasInfo: tokenInfoProvider.hasInfo(token: token, isEnabled: isEnabled)
            ),
            isEnabled
        )
    }

    private func handleWalletsUpdated(_ newWallets: [Wallet]) {
        wallets = Set(newWallets)
        reloadItems()
    }

    private func handleApproveRestoreSettings(token: Token, settings: RestoreSettings) {
        if !settings.isEmpty {
            restoreSettingsService.save(settings: settings, account: account, blockchainType: token.blockchainType)
        }

        saveWallet(for: token)
    }

    private func saveWallet(for token: Token) {
        let wallet = Wallet(token: token, account: account)
        walletManager.save(wallets: [wallet])
    }

    private var allowedBlockchainTypes: [BlockchainType]? {
        blockchainFilter.map { [$0.type] } ?? childWalletBlockchainTypes
    }
}

extension ManageWalletsViewModel {
    var blockchainFilterIndex: Int {
        guard let blockchainFilter, let index = blockchains.firstIndex(of: blockchainFilter) else { // all
            return 0
        }

        return index + 1
    }

    func setBlockchainFilter(index: Int) {
        if index <= 0 {
            blockchainFilter = nil
        } else {
            blockchainFilter = blockchains[index - 1]
        }
    }

    func toggle(item: Item, enabled: Bool) {
        if enabled {
            enable(token: item.token)
        } else {
            disable(token: item.token)
        }
    }

    func showInfo(item: Item) -> ManageWalletsTokenInfoProvider.InfoItem? {
        guard let infoItem = tokenInfoProvider.infoItem(token: item.token, accountId: account.id) else {
            return nil
        }

        stat(page: .coinManager, event: .openTokenInfo(token: item.token))

        return infoItem
    }

    func addTokenInput() -> (Account, [AddTokenModule.Item])? {
        let items = AddTokenModule.items(account: account)
        guard !items.isEmpty else {
            return nil
        }

        return (account, items)
    }

    private func enable(token: Token) {
        if !token.blockchainType.restoreSettingTypes.isEmpty {
            restoreSettingsService.approveSettings(token: token, account: account)
        } else {
            saveWallet(for: token)
            stat(page: .coinManager, event: .enableToken(token: token))
        }
    }

    private func disable(token: Token) {
        let walletsToDelete = wallets.filter { $0.token == token }
        walletManager.delete(wallets: Array(walletsToDelete))
        stat(page: .coinManager, event: .disableToken(token: token))
    }
}

extension ManageWalletsViewModel {
    struct Item: Identifiable, Equatable, Hashable {
        let token: Token
        let hasInfo: Bool

        var id: Int { token.hashValue }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.hasInfo == rhs.hasInfo
        }
    }
}
