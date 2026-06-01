import Foundation
import Combine
import RxCocoa
import RxSwift
import SwiftUI
import UIKit

@MainActor
final class NftV2ViewModel: ObservableObject {
    private static let regularRefreshInterval: RxTimeInterval = .seconds(20)
    private static let sendFollowUpIntervals: [UInt64] = [
        1_000_000_000,
        2_500_000_000,
        5_000_000_000
    ]

    struct ChainSection: Identifiable {
        let chainState: NftV2ChainState
        let pendingTransfers: [NftV2PendingTransferItem]
        let collections: [NftV2Collection]

        var id: String {
            chainState.id
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case favorites

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all: return "nft_v2.filter.all".localized
            case .favorites: return "nft_v2.filter.favorites".localized
            }
        }
    }

    enum State {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var filter: Filter = .all
    @Published private(set) var state: State = .idle
    @Published private(set) var collections = [NftV2Collection]()
    @Published private(set) var chainStates = [NftV2ChainState]()
    @Published private(set) var pendingTransfers = [NftV2PendingTransferItem]()
    @Published private(set) var sendCapabilityByAssetKey = [String: NftV2SendCapability]()
    @Published private(set) var sendingAssetKeys = Set<String>()

    private let inventoryService: NftV2InventoryService
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshDisposable: Disposable?
    private var sendCapabilityTasks = [String: Task<Void, Never>]()
    private var sendFollowUpTask: Task<Void, Never>?
    private var lastAccountId: String?
    private var isVisible = false
    private var rawCollections = [NftV2Collection]()

    init(inventoryService: NftV2InventoryService) {
        self.inventoryService = inventoryService
        bindInventoryUpdates()
        bindAccountChanges()
        bindTransactionChanges()
    }

    var visibleCollections: [NftV2Collection] {
        switch filter {
        case .all:
            return collections
        case .favorites:
            return collections.filter { inventoryService.isFavorite(collectionId: $0.id) }
        }
    }

    var hasDegradedChain: Bool {
        chainStates.contains {
            if case .unavailable = $0.status {
                return true
            }

            return false
        }
    }

    var chainSections: [ChainSection] {
        let groupedCollections = Dictionary(grouping: visibleCollections, by: \.chain)
        let groupedPendingTransfers = Dictionary(grouping: visiblePendingTransfers, by: \.chain)

        return chainStates.map { chainState in
            ChainSection(
                chainState: chainState,
                pendingTransfers: groupedPendingTransfers[chainState.chain] ?? [],
                collections: groupedCollections[chainState.chain] ?? []
            )
        }
    }

    var hasVisibleContent: Bool {
        !visiblePendingTransfers.isEmpty || !visibleCollections.isEmpty
    }

    private var visiblePendingTransfers: [NftV2PendingTransferItem] {
        switch filter {
        case .all:
            return pendingTransfers
        case .favorites:
            return pendingTransfers.filter { inventoryService.isFavorite(collectionId: $0.collectionId) }
        }
    }

    func favoriteCount(chain: NftV2Chain) -> Int {
        collections
            .filter { $0.chain == chain && inventoryService.isFavorite(collectionId: $0.id) }
            .reduce(0) { $0 + $1.count }
    }

    func onAppear() {
        handleAccountChangedIfNeeded()
        inventoryService.syncFavorites()

        guard !isVisible else {
            return
        }

        isVisible = true
        startAutoRefresh()

        if case .idle = state {
            reload()
        }
    }

    func onDisappear() {
        isVisible = false
        autoRefreshDisposable?.dispose()
        autoRefreshDisposable = nil
        sendFollowUpTask?.cancel()
        sendFollowUpTask = nil
        sendCapabilityTasks.values.forEach { $0.cancel() }
        sendCapabilityTasks.removeAll()
    }

    func reload() {
        handleAccountChangedIfNeeded()

        if !collections.isEmpty || !chainStates.isEmpty {
            state = .loaded
        } else {
            state = .loading
        }

        inventoryService.refresh()
    }

    private func bindInventoryUpdates() {
        inventoryService.snapshotObservable()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] snapshot in
                guard let self else {
                    return
                }

                sync(snapshot: snapshot)
            })
            .disposed(by: disposeBag)
    }

    private func startAutoRefresh() {
        autoRefreshDisposable?.dispose()

        let timer = Observable<Int>.interval(Self.regularRefreshInterval, scheduler: MainScheduler.instance)
        let foreground = NotificationCenter.default.rx.notification(UIApplication.willEnterForegroundNotification)
            .map { _ in 0 }
        let trigger = Observable.merge(timer, foreground)

        autoRefreshDisposable = trigger
            .subscribe(onNext: { [weak self] _ in
                guard let self, self.isVisible else {
                    return
                }

                self.reload()
            })
    }

    private func resolvedState(for snapshot: NftV2Snapshot) -> State {
        if snapshot.collections.isEmpty,
           snapshot.chainStates.contains(where: { $0.isRefreshing && $0.address != nil })
        {
            return .loading
        }

        return .loaded
    }

    func toggleFavorite(collection: NftV2Collection) {
        inventoryService.toggleFavorite(collectionId: collection.id)
        collections = collections.sorted { lhs, rhs in
            if inventoryService.isFavorite(collectionId: lhs.id) != inventoryService.isFavorite(collectionId: rhs.id) {
                return inventoryService.isFavorite(collectionId: lhs.id)
            }

            if lhs.chain != rhs.chain {
                return lhs.chain.sortIndex < rhs.chain.sortIndex
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func isFavorite(collection: NftV2Collection) -> Bool {
        inventoryService.isFavorite(collectionId: collection.id)
    }

    func sendCapability(asset: NftV2Asset) -> NftV2SendCapability {
        handleAccountChangedIfNeeded()

        if isSending(asset: asset) {
            return .blocked(reason: .syncing)
        }

        let key = capabilityKey(asset: asset)
        if let capability = sendCapabilityByAssetKey[key] {
            return capability
        }

        let initial = inventoryService.initialSendCapability(asset: asset)
        sendCapabilityByAssetKey[key] = initial
        return initial
    }

    func refreshSendCapabilityIfNeeded(asset: NftV2Asset) {
        handleAccountChangedIfNeeded()

        let key = capabilityKey(asset: asset)
        let current = sendCapability(asset: asset)
        let needsRefresh: Bool
        switch current {
        case .checking:
            needsRefresh = true
        case .blocked(.syncing):
            needsRefresh = true
        case .blocked(.unavailable):
            needsRefresh = !isSending(asset: asset)
        case .ready:
            needsRefresh = false
        }

        guard needsRefresh else {
            return
        }

        if sendCapabilityTasks[key] != nil {
            return
        }

        sendCapabilityByAssetKey[key] = .checking
        sendCapabilityTasks[key] = Task { [weak self] in
            guard let self else {
                return
            }

            let refreshed = await inventoryService.refreshSendCapability(asset: asset)

            await MainActor.run {
                guard !Task.isCancelled else {
                    self.sendCapabilityTasks[key] = nil
                    return
                }

                self.sendCapabilityByAssetKey[key] = refreshed
                self.sendCapabilityTasks[key] = nil
            }
        }
    }

    func sendValidationMessage(asset: NftV2Asset) -> String {
        switch sendCapability(asset: asset) {
        case .ready:
            return "nft_v2.send.unavailable".localized
        case .checking:
            return "nft_v2.send.syncing".localized
        case let .blocked(reason):
            switch reason {
            case .syncing:
                return isSending(asset: asset)
                    ? "send.confirmation.sending".localized
                    : "nft_v2.send.syncing".localized
            case .unavailable:
                return "nft_v2.send.unavailable".localized
            }
        }
    }

    func validatedSendController(
        asset: NftV2Asset,
        collection: NftV2Collection,
        onSendSuccess: @escaping (NftV2Asset, NftV2Collection, String, Int) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) async -> UIViewController? {
        handleAccountChangedIfNeeded()

        let requestAccountId = inventoryService.activeAccountId
        let key = capabilityKey(asset: asset)
        let refreshed = await inventoryService.refreshSendCapability(asset: asset)
        guard requestAccountId == inventoryService.activeAccountId else {
            return nil
        }
        sendCapabilityByAssetKey[key] = refreshed

        guard refreshed.isReady else {
            return nil
        }

        return inventoryService.sendController(
            asset: asset,
            onSendSuccess: { txHash, amount in
                onSendSuccess(asset, collection, txHash.hs.hexString, amount)
            },
            onSendFailed: onSendFailed
        )
    }

    func legacyController() -> UIViewController {
        inventoryService.legacyController()
    }

    func isChainSynced(chain: NftV2Chain) -> Bool {
        chainStates.first(where: { $0.chain == chain })?.isActionEnabled ?? false
    }

    func isChainRefreshing(chain: NftV2Chain) -> Bool {
        chainStates.first(where: { $0.chain == chain })?.isRefreshing ?? false
    }

    func isSending(asset: NftV2Asset) -> Bool {
        sendingAssetKeys.contains(capabilityKey(asset: asset)) || pendingTransfers.contains(where: { $0.asset.id == asset.id })
    }

    func markSending(asset: NftV2Asset, sending: Bool) {
        let key = capabilityKey(asset: asset)
        if sending {
            sendingAssetKeys.insert(key)
            sendCapabilityByAssetKey[key] = .blocked(reason: .syncing)
        } else {
            sendingAssetKeys.remove(key)
            sendCapabilityByAssetKey.removeValue(forKey: key)
        }
    }

    func handleSendSuccess(asset: NftV2Asset, collection: NftV2Collection, transactionHash: String, amount: Int) {
        markSending(asset: asset, sending: false)
        inventoryService.savePendingTransfer(asset: asset, collection: collection, amount: amount, transactionHash: transactionHash)
        reloadPendingTransfers()
        refreshPresentation()
        reload()
        refreshAfterSend(asset: asset)
    }

    func completeSendPresentation(asset: NftV2Asset) {
        markSending(asset: asset, sending: false)

        if !pendingTransfers.contains(where: { $0.asset.id == asset.id }) {
            refreshSendCapabilityIfNeeded(asset: asset)
        }

        reload()
    }

    func refreshAfterSend(asset: NftV2Asset) {
        sendFollowUpTask?.cancel()
        sendFollowUpTask = Task { [weak self] in
            guard let self else {
                return
            }

            await MainActor.run {
                self.reload()
            }

            for delayNs in Self.sendFollowUpIntervals {
                try? await Task.sleep(nanoseconds: delayNs)
                await MainActor.run {
                    self.reload()
                    self.refreshSendCapabilityIfNeeded(asset: asset)
                }
            }

            await MainActor.run {
                self.sendFollowUpTask = nil
            }
        }
    }

    private func capabilityKey(asset: NftV2Asset) -> String {
        let accountId = inventoryService.activeAccountId ?? "none"
        return "\(accountId)|\(asset.id)"
    }

    @discardableResult
    private func handleAccountChangedIfNeeded() -> Bool {
        let currentAccountId = inventoryService.activeAccountId
        guard currentAccountId != lastAccountId else {
            return false
        }

        lastAccountId = currentAccountId
        sendCapabilityTasks.values.forEach { $0.cancel() }
        sendCapabilityTasks.removeAll()
        sendFollowUpTask?.cancel()
        sendFollowUpTask = nil
        sendCapabilityByAssetKey.removeAll()
        sendingAssetKeys.removeAll()
        pendingTransfers = []
        state = .idle
        inventoryService.syncFavorites()
        reloadPendingTransfers()
        sync(snapshot: inventoryService.currentSnapshot)
        return true
    }

    private func bindAccountChanges() {
        inventoryService.activeAccountIdPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                guard handleAccountChangedIfNeeded() else {
                    return
                }

                if isVisible {
                    reload()
                }
            }
            .store(in: &cancellables)
    }

    private func bindTransactionChanges() {
        inventoryService.transactionRecordsObservable()
            .throttle(.milliseconds(400), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] chain, records in
                self?.reconcilePendingTransfers(chain: chain, records: records)
            })
            .disposed(by: disposeBag)
    }

    private func reloadPendingTransfers() {
        pendingTransfers = inventoryService.pendingTransfers()
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    private func reconcilePendingTransfers(chain: NftV2Chain, records: [TransactionRecord]) {
        guard !pendingTransfers.isEmpty else {
            return
        }

        var transactionByHash = [String: TransactionRecord]()
        for record in records {
            transactionByHash[record.transactionHash.lowercased()] = record
        }

        let matched = pendingTransfers.filter { pending in
            guard pending.chain == chain,
                  let record = transactionByHash[pending.transactionHash.lowercased()]
            else {
                return false
            }

            if record.failed {
                return true
            }

            guard record.blockHeight != nil else {
                return false
            }

            return pendingTransferIsApplied(pending)
        }

        guard !matched.isEmpty else {
            return
        }

        matched.forEach { inventoryService.removePendingTransfer(chain: $0.chain, transactionHash: $0.transactionHash) }
        reloadPendingTransfers()
        refreshPresentation()
        reload()
    }

    private func refreshPresentation() {
        collections = applyPendingTransfers(to: rawCollections)
        refreshCapabilitiesForVisibleAssets()
    }

    private func sync(snapshot: NftV2Snapshot) {
        rawCollections = snapshot.collections
        chainStates = snapshot.chainStates
        refreshPresentation()
        state = resolvedState(for: snapshot)
    }

    private func refreshCapabilitiesForVisibleAssets() {
        let visibleAssets = Set(visibleCollections.flatMap(\.items).map(capabilityKey(asset:)))

        for (key, task) in sendCapabilityTasks where !visibleAssets.contains(key) {
            task.cancel()
            sendCapabilityTasks[key] = nil
        }

        let assetsByChain = Dictionary(grouping: visibleCollections.flatMap(\.items), by: \.chain)
        for (chain, assets) in assetsByChain {
            guard !assets.isEmpty else {
                continue
            }

            if isChainRefreshing(chain: chain) {
                for asset in assets where sendCapability(asset: asset) != .ready && !isSending(asset: asset) {
                    sendCapabilityByAssetKey[capabilityKey(asset: asset)] = .checking
                }
                continue
            }

            for asset in assets where !isSending(asset: asset) {
                refreshSendCapabilityIfNeeded(asset: asset)
            }
        }
    }

    private func pendingTransferIsApplied(_ pending: NftV2PendingTransferItem) -> Bool {
        guard let rawCollection = rawCollections.first(where: { $0.id == pending.collectionId }) else {
            return true
        }

        guard let rawAsset = rawCollection.items.first(where: { $0.id == pending.asset.id }) else {
            return true
        }

        let expectedBalance = max(pending.asset.balance - max(pending.amount, 1), 0)
        return rawAsset.balance <= expectedBalance
    }

    private func applyPendingTransfers(to collections: [NftV2Collection]) -> [NftV2Collection] {
        guard !pendingTransfers.isEmpty else {
            return collections
        }

        var result = collections

        for pending in pendingTransfers {
            guard let collectionIndex = result.firstIndex(where: { $0.id == pending.collectionId }) else {
                continue
            }

            var collection = result[collectionIndex]
            guard let itemIndex = collection.items.firstIndex(where: { $0.id == pending.asset.id }) else {
                continue
            }

            var items = collection.items
            let current = items[itemIndex]
            let remainingBalance = max(current.balance - max(pending.amount, 1), 0)

            if remainingBalance == 0 {
                items.remove(at: itemIndex)
            } else {
                items[itemIndex] = NftV2Asset(
                    id: current.id,
                    nftUid: current.nftUid,
                    chain: current.chain,
                    contractAddress: current.contractAddress,
                    tokenId: current.tokenId,
                    standard: current.standard,
                    name: current.name,
                    imageUrl: current.imageUrl,
                    collectionName: current.collectionName,
                    market: current.market,
                    marketUrl: current.marketUrl,
                    balance: remainingBalance,
                    canSend: current.canSend,
                    transferType: current.transferType
                )
            }

            if items.isEmpty {
                result.remove(at: collectionIndex)
            } else {
                result[collectionIndex] = NftV2Collection(
                    id: collection.id,
                    chain: collection.chain,
                    contractAddress: collection.contractAddress,
                    name: collection.name,
                    imageUrl: collection.imageUrl,
                    market: collection.market,
                    marketUrl: collection.marketUrl,
                    items: items
                )
            }
        }

        return result
    }
}
