import Combine
import Foundation
import MarketKit
import RxSwift

class WalletListViewModel: ObservableObject {
    private let keySortType = "wallet-sort-type"

    private let walletServiceFactory = WalletServiceFactory()
    let coinPriceService = WalletCoinPriceService()
    private let sorter = WalletSorter()
    let balanceHiddenManager = Core.shared.balanceHiddenManager
    let accountManager = Core.shared.accountManager
    private let reachabilityManager = Core.shared.reachabilityManager
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cacheManager = Core.shared.enabledWalletCacheManager
    private let feeCoinProvider = Core.shared.feeCoinProvider
    private let appSettingManager = Core.shared.appSettingManager
    private let amountRoundingManager = Core.shared.amountRoundingManager

    let disposeBag = DisposeBag()
    var cancellables = Set<AnyCancellable>()

    @Published private(set) var account: Account?
    @Published private(set) var balancePrimaryValue: BalancePrimaryValue
    @Published private(set) var balanceHidden: Bool
    @Published private(set) var amountRounding: Bool

    @Published var sortType: WalletSorter.SortType {
        didSet {
            handleUpdateSortType()
            userDefaultsStorage.set(value: sortType.rawValue, for: keySortType)
        }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isReachable: Bool = true

    var walletService: WalletService?

    var __items: [Item] = []
    let queue = DispatchQueue(label: "\(AppConfig.label).wallet-list-view-model", qos: .userInitiated)
    private let safeWalletRefreshInterval: TimeInterval = 3.5
    private var safeWalletRefreshScheduled = false
    private var pendingSafeWalletNeedsSort = false
    private var pendingSafeWalletNeedsTotalSync = false
    private var safeWalletSettling = Set<Wallet>()

    init() {
        if let rawValue: String = userDefaultsStorage.value(for: keySortType), let sortType = WalletSorter.SortType(rawValue: rawValue) {
            self.sortType = sortType
        } else {
            sortType = .balance
        }

        account = accountManager.activeAccount
        balancePrimaryValue = appSettingManager.balancePrimaryValue
        balanceHidden = balanceHiddenManager.balanceHidden
        amountRounding = amountRoundingManager.useAmountRounding
        isReachable = reachabilityManager.isReachable

        coinPriceService.delegate = self

        accountManager.activeAccountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleUpdated(activeAccount: $0) }
            .store(in: &cancellables)

        accountManager.accountUpdatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleUpdated(account: $0) }
            .store(in: &cancellables)

        appSettingManager.balancePrimaryValueObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.balancePrimaryValue = $0
            })
            .disposed(by: disposeBag)

        balanceHiddenManager.balanceHiddenObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.balanceHidden = $0
            })
            .disposed(by: disposeBag)

        amountRoundingManager.amountRoundingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.amountRounding = $0
            }
            .store(in: &cancellables)

        reachabilityManager.$isReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isReachable = $0 }
            .store(in: &cancellables)

        _syncWalletService()
    }

    private func handleUpdated(activeAccount: Account?) {
        let accountChanged = account?.id != activeAccount?.id
        account = activeAccount

        queue.async {
            if accountChanged {
                self._clearItemsForAccountSwitch()
            }
            self._syncWalletService()
        }
    }

    private func handleUpdated(account: Account) {
        if account.id == self.account?.id {
            self.account = account
        }
    }

    private func handleUpdateSortType() {
        queue.async {
            self._sortItems()
            self._reportItems()
        }
    }

    private func _sortItems() {
        __items = sorter.sort(items: __items, sortType: sortType)
    }

    private func _reportItems() {
        DispatchQueue.main.async { [weak self, __items] in
            self?.items = __items
        }
    }

    private func _itemIndex(wallet: Wallet) -> Int? {
        __items.firstIndex { $0.wallet == wallet }
    }

    private func _shouldThrottleSafeWalletUpdate(wallet: Wallet) -> Bool {
        guard wallet.token.blockchainType == .safe, let index = _itemIndex(wallet: wallet) else {
            return false
        }

        return __items[index].state.syncing || safeWalletSettling.contains(wallet)
    }

    private func _markSafeWalletSettling(wallet: Wallet) {
        guard wallet.token.blockchainType == .safe else {
            return
        }

        safeWalletSettling.insert(wallet)

        queue.asyncAfter(deadline: .now() + safeWalletRefreshInterval) {
            self.safeWalletSettling.remove(wallet)
        }
    }

    private func _scheduleSafeWalletRefresh(needsSort: Bool, needsTotalSync: Bool) {
        pendingSafeWalletNeedsSort = pendingSafeWalletNeedsSort || needsSort
        pendingSafeWalletNeedsTotalSync = pendingSafeWalletNeedsTotalSync || needsTotalSync

        guard !safeWalletRefreshScheduled else {
            return
        }

        safeWalletRefreshScheduled = true

        queue.asyncAfter(deadline: .now() + safeWalletRefreshInterval) {
            self.safeWalletRefreshScheduled = false

            guard self.pendingSafeWalletNeedsSort || self.pendingSafeWalletNeedsTotalSync else {
                return
            }

            if self.pendingSafeWalletNeedsSort {
                self._sortItems()
            }

            let needsTotalSync = self.pendingSafeWalletNeedsTotalSync
            self.pendingSafeWalletNeedsSort = false
            self.pendingSafeWalletNeedsTotalSync = false

            self._reportItems()

            if needsTotalSync {
                self._syncTotalItem()
            }
        }
    }

    private func _syncWalletService() {
        walletService?.delegate = nil

        if let account {
            let walletService = walletServiceFactory.walletService(account: account)
            walletService.delegate = self
            self.walletService = walletService

            _sync(wallets: walletService.wallets, walletService: walletService)
        } else {
            walletService = nil
            __items = []
            _reportItems()
        }
    }

    private func _clearItemsForAccountSwitch() {
        walletService?.delegate = nil
        walletService = nil
        __items = []
        _reportItems()
        _syncTotalItem()
    }

    private func _sync(wallets: [Wallet], walletService: WalletService) {
        let cacheContainer = account.map { cacheManager.cacheContainer(accountId: $0.id) }
        let priceItemMap = coinPriceService.itemMap(coinUids: wallets.compactMap(\.priceCoinUid))

        __items = wallets.map { wallet in
            var item = Item(
                wallet: wallet,
                isMainNet: walletService.isMainNet(wallet: wallet) ?? fallbackIsMainNet,
                balanceData: walletService.balanceData(wallet: wallet) ?? _cachedBalanceData(wallet: wallet, cacheContainer: cacheContainer) ?? fallbackBalanceData,
                caution: walletService.caution(wallet: wallet),
                state: walletService.state(wallet: wallet) ?? fallbackAdapterState
            )

            if let priceCoinUid = wallet.priceCoinUid {
                item.priceItem = priceItemMap[priceCoinUid]
            }

            return item
        }

        _sortItems()
        _reportItems()

        _syncTotalItem()

        coinPriceService.set(
            coinUids: Set(wallets.compactMap(\.priceCoinUid)),
            feeCoinUids: Set(wallets.compactMap { feeCoinProvider.feeToken(token: $0.token) }.map(\.coin.uid)),
            conversionCoinUids: conversionCoinUids
        )
    }

    private func _cachedBalanceData(wallet: Wallet, cacheContainer: EnabledWalletCacheManager.CacheContainer?) -> BalanceData? {
        cacheContainer?.balanceData(wallet: wallet)
    }

    private var fallbackIsMainNet: Bool {
        true
    }

    private var fallbackBalanceData: BalanceData {
        BalanceData(balance: 0)
    }

    private var fallbackAdapterState: AdapterState {
        .syncing(progress: nil, remaining: nil, lastBlockDate: nil)
    }

    var conversionCoinUids: Set<String> {
        []
    }

    func _syncTotalItem() {}
}

extension WalletListViewModel: IWalletServiceDelegate {
    func didUpdateWallets(walletService: WalletService) {
        queue.async {
            guard self.walletService === walletService, self.account?.id == walletService.accountId else {
                return
            }

            var balanceDataMap = [Wallet: BalanceData]()

            for index in self.__items.indices {
                let wallet = self.__items[index].wallet

                let balanceData = walletService.balanceData(wallet: wallet) ?? self.fallbackBalanceData

                self.__items[index].isMainNet = walletService.isMainNet(wallet: wallet) ?? self.fallbackIsMainNet
                self.__items[index].balanceData = balanceData
                self.__items[index].state = walletService.state(wallet: wallet) ?? self.fallbackAdapterState

                balanceDataMap[wallet] = balanceData
            }

            self._sortItems()
            self._reportItems()

            self._syncTotalItem()

            if !balanceDataMap.isEmpty {
                self.cacheManager.set(balanceDataMap: balanceDataMap)
            }
        }
    }

    func didUpdate(wallets: [Wallet], walletService: WalletService) {
        queue.async {
            guard self.walletService === walletService, self.account?.id == walletService.accountId else {
                return
            }

            self._sync(wallets: wallets, walletService: walletService)
        }
    }

    func didUpdate(isMainNet: Bool, wallet: Wallet) {
        queue.async {
            guard let index = self._itemIndex(wallet: wallet) else {
                return
            }

            self.__items[index].isMainNet = isMainNet
            self._reportItems()
        }
    }

    func didUpdate(balanceData: BalanceData, wallet: Wallet) {
        queue.async {
            guard let index = self._itemIndex(wallet: wallet) else {
                return
            }

            self.__items[index].balanceData = balanceData
            let needsSort = self.sortType == .balance && self.__items.allSatisfy(\.state.isSynced)

            self.cacheManager.set(balanceData: balanceData, wallet: wallet)

            if self._shouldThrottleSafeWalletUpdate(wallet: wallet) {
                self._scheduleSafeWalletRefresh(needsSort: needsSort, needsTotalSync: true)
                return
            }

            if needsSort {
                self._sortItems()
            }

            self._reportItems()
            self._syncTotalItem()
        }
    }

    func didUpdate(state: AdapterState, wallet: Wallet) {
        queue.async {
            guard let index = self._itemIndex(wallet: wallet) else {
                return
            }

            let oldState = self.__items[index].state
            self.__items[index].state = state
            let needsSort = self.sortType == .balance && self.__items.allSatisfy(\.state.isSynced)
            let needsTotalSync = oldState.isSynced != state.isSynced

            if oldState.syncing && !state.syncing {
                self._markSafeWalletSettling(wallet: wallet)
            }

            if self._shouldThrottleSafeWalletUpdate(wallet: wallet) {
                self._scheduleSafeWalletRefresh(needsSort: needsSort, needsTotalSync: needsTotalSync)
                return
            }

            if needsSort {
                self._sortItems()
            }

            self._reportItems()

            if needsTotalSync {
                self._syncTotalItem()
            }
        }
    }

    func didUpdate(caution: CautionNew?, wallet: Wallet) {
        queue.async {
            guard let index = self._itemIndex(wallet: wallet) else {
                return
            }

            self.__items[index].caution = caution

            self._reportItems()
        }
    }
}

extension WalletListViewModel: IWalletCoinPriceServiceDelegate {
    private func _handleUpdated(priceItemMap: [String: WalletCoinPriceService.Item]) {
        for index in __items.indices {
            if let priceCoinUid = __items[index].wallet.priceCoinUid {
                __items[index].priceItem = priceItemMap[priceCoinUid]
            }
        }

        _sortItems()
        _reportItems()
        _syncTotalItem()
    }

    func didUpdate(itemsMap: [String: WalletCoinPriceService.Item]?) {
        queue.async {
            let _itemsMap: [String: WalletCoinPriceService.Item]
            if let itemsMap {
                _itemsMap = itemsMap
            } else {
                let coinUids = Array(Set(self.__items.compactMap(\.wallet.priceCoinUid)))
                _itemsMap = self.coinPriceService.itemMap(coinUids: coinUids)
            }

            self._handleUpdated(priceItemMap: _itemsMap)
        }
    }
}

extension WalletListViewModel {
    struct Item: Hashable, ISortableWalletItem {
        let wallet: Wallet
        var isMainNet: Bool
        var balanceData: BalanceData
        var caution: CautionNew?
        var state: AdapterState
        var priceItem: WalletCoinPriceService.Item?

        var balance: Decimal {
            balanceData.available
        }

        var name: String {
            wallet.coin.name
        }

        var diff: Decimal? {
            priceItem?.diff
        }
    }
}
