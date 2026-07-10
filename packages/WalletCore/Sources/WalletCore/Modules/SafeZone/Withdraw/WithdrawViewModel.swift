import Combine
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

private let WithdrawIdsKey = "safe4_WithdrawIds_key"
private let RemoveVoteIdsKey = "safe4_RemoveVoteIds_key"
private let WithdrawCacheTimestampKey = "safe4_withdraw_cache_timestamp_key"
private let WithdrawCacheSnapshotKey = "safe4_withdraw_cache_snapshot_key"

class WithdrawViewModel: ObservableObject {
    private static let pageSize = 20
    private static let cacheMaxAge: TimeInterval = 120
    private static let withdrawBatchSize = 30
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let service: WithdrawViewService
    private let withdrawLockedStorage: Safe4WithdrawLockedStorage
    private let userDefaultsStorage = Core.shared.userDefaultsStorage

    private var pageControl = Safe4PageControl(pageSize: pageSize)
    private var cachedTotal = 0
    private var requestedCount = 0
    private var withdrawTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    private var requestContextId = UUID()
    private var pendingRemovedIds = Set<BigUInt>()
    private var isLoadingMoreInternal = false

    @Published private(set) var sendState: SendStatus = .normal
    @Published private(set) var dataState: ListState = .items
    @Published private(set) var hasMoreItems = true
    @Published private(set) var viewItems: [WithdrawItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published var selectedItems: [WithdrawItem] = [] {
        didSet {
            withdrawEnabled = !selectedItems.isEmpty
        }
    }
    @Published var withdrawEnabled = false
    @Published var isLoadAll = false

    var onSuccess: ((SendStatus) -> Void)?

    init(service: WithdrawViewService, withdrawLockedStorage: Safe4WithdrawLockedStorage) {
        self.service = service
        self.withdrawLockedStorage = withdrawLockedStorage
        restoreCache()
        initialLoad()
    }
}

extension WithdrawViewModel {
    func choose(item: WithdrawItem) {
        if let index = selectedItems.firstIndex(where: { $0.id == item.id }) {
            selectedItems.remove(at: index)
        } else {
            selectedItems.append(item)
        }
    }

    func isSelected(item: WithdrawItem) -> Bool {
        selectedItems.contains(where: { $0.id == item.id })
    }

    @MainActor
    func refresh() async {
        await withCheckedContinuation { continuation in
            if !startListRequest(kind: .refresh, onComplete: { continuation.resume() }) {
                continuation.resume()
            }
        }
    }

    func loadMore() {
        _ = startListRequest(kind: .loadMore)
    }

    func withdraw() {
        guard withdrawTask == nil else { return }
        guard !selectedItems.isEmpty else { return }

        sendState = .loading
        withdrawEnabled = false
        let snapshot = selectedItems

        withdrawTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.withdrawTask = nil
                }
            }

            do {
                if service.type == .voteLocked {
                    let removeVoteIds = snapshot.filter(\.isRemoveVoteEnable).map(\.id)
                    if !removeVoteIds.isEmpty {
                        for chunk in removeVoteIds.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                            _ = try await service.removeVoteOrApproval(recordIDs: chunk)
                        }
                        WithdrawViewModel.saveRemoveVoteIds(removeVoteIds.map(\.description))
                    }

                    let withdrawIds = snapshot.filter(\.isWithdrawEnable).map(\.id)
                    if !withdrawIds.isEmpty {
                        for chunk in withdrawIds.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                            _ = try await service.withdrawByID(type: .native, ids: chunk)
                        }
                        WithdrawViewModel.saveDidWithdrawIds(withdrawIds.map(\.description))
                    }
                } else {
                    let ids = snapshot.map(\.id)
                    for chunk in ids.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                        _ = try await service.withdrawByID(type: .native, ids: chunk)
                    }
                    WithdrawViewModel.saveDidWithdrawIds(ids.map(\.description))
                }

                await MainActor.run {
                    applyLocalWithdrawSuccess(items: snapshot)
                    selectedItems.removeAll()
                    sendState = .completed
                    withdrawEnabled = true
                    onSuccess?(sendState)
                }
            } catch {
                await MainActor.run {
                    withdrawEnabled = true
                    sendState = .failed(RequestError.withdrawError)
                    onSuccess?(sendState)
                }
            }
        }
    }

    func chooseAll() {
        selectedItems = enableItems
    }

    func cancelAll() {
        selectedItems.removeAll()
    }

    func allWithdraw() {
        selectedItems = enableItems
        withdraw()
    }

    var enableItems: [WithdrawItem] {
        viewItems.filter(\.isSelEnable)
    }

    var isChoosedAll: Bool {
        !enableItems.isEmpty && selectedItems == enableItems
    }

    var title: String {
        service.type.title
    }

    var withdrawType: SafeWithdrawType {
        service.type
    }
}

private extension WithdrawViewModel {
    enum RequestKind {
        case initial
        case refresh
        case loadMore
    }

    struct CacheSnapshot: Codable {
        let totalNum: Int
        let requestedCount: Int
    }

    @discardableResult
    func startListRequest(kind: RequestKind, onComplete: (() -> Void)? = nil) -> Bool {
        switch kind {
        case .initial:
            guard listTask == nil else {
                onComplete?()
                return false
            }
        case .refresh:
            listTask?.cancel()
            listTask = nil
        case .loadMore:
            guard listTask == nil, !isRefreshing, !isLoadingMoreInternal, hasMoreItems else {
                onComplete?()
                return false
            }
        }

        let requestId = UUID()
        requestContextId = requestId
        isRefreshing = kind == .refresh
        isLoadingMoreInternal = kind == .loadMore
        isLoadingNextPage = kind == .loadMore
        dataState = .loading

        let currentItems = viewItems
        let currentCachedTotal = cachedTotal
        let currentRequestedCount = requestedCount
        let cacheExpired = isCacheExpired(maxAge: Self.cacheMaxAge)

        listTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.finishListRequest(requestId: requestId)
                    onComplete?()
                }
            }

            do {
                let latestTotal = try await fetchLatestTotal()
                let nextState: (items: [WithdrawItem], total: Int, requested: Int)

                switch kind {
                case .initial:
                    let shouldReload =
                        currentItems.isEmpty ||
                        cacheExpired ||
                        latestTotal != currentCachedTotal
                    if shouldReload {
                        nextState = try await rebuildItems(latestTotal: latestTotal, requestedCount: currentRequestedCount)
                    } else {
                        nextState = (
                            items: currentItems,
                            total: latestTotal,
                            requested: min(currentRequestedCount, latestTotal)
                        )
                    }
                case .refresh:
                    nextState = try await rebuildItems(latestTotal: latestTotal, requestedCount: currentRequestedCount)
                case .loadMore:
                    if latestTotal != currentCachedTotal {
                        nextState = try await rebuildItems(latestTotal: latestTotal, requestedCount: currentRequestedCount)
                    } else {
                        nextState = try await loadMoreItems(
                            currentItems: currentItems,
                            latestTotal: latestTotal,
                            requestedCount: currentRequestedCount
                        )
                    }
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.requestContextId == requestId else { return }
                    self.apply(
                        items: nextState.items,
                        total: nextState.total,
                        requestedCount: nextState.requested
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.requestContextId == requestId else { return }
                    if self.viewItems.isEmpty {
                        self.dataState = .error(RequestError.getInfo as NSError)
                    } else {
                        self.dataState = .items
                    }
                }
            }
        }

        return true
    }

    func finishListRequest(requestId: UUID) {
        guard requestContextId == requestId else { return }
        listTask = nil
        isRefreshing = false
        isLoadingMoreInternal = false
        isLoadingNextPage = false
    }

    func initialLoad() {
        _ = startListRequest(kind: .initial)
    }

    func fetchLatestTotal() async throws -> Int {
        let totalNum: BigUInt

        switch service.type {
        case .masterNode, .superNode:
            totalNum = try await service.totalNum(type: .native)
        case .proposal:
            totalNum = try await service.mineProposalNum()
        case .voteLocked:
            totalNum = try await service.getVotedIDNum4Voter()
        }

        return Int(totalNum)
    }

    func rebuildItems(latestTotal: Int, requestedCount: Int) async throws -> (items: [WithdrawItem], total: Int, requested: Int) {
        guard latestTotal > 0 else {
            return ([], 0, 0)
        }

        let targetRequestedCount = min(max(requestedCount, min(Self.pageSize, latestTotal)), latestTotal)
        var pageControl = Safe4PageControl(pageSize: Self.pageSize)
        pageControl.set(totalNum: latestTotal)
        var accumulatedItems = [WithdrawItem]()
        var consumedCount = 0

        while consumedCount < targetRequestedCount, pageControl.isAbleLoadMore {
            let pageResult = try await fetchPage(pageControl: &pageControl)
            consumedCount += pageResult.requestedCount
            accumulatedItems.append(contentsOf: pageResult.items)

            if pageResult.requestedCount == 0, !pageControl.isAbleLoadMore {
                break
            }
        }

        return (
            dedupAndSort(items: accumulatedItems),
            latestTotal,
            min(consumedCount, latestTotal)
        )
    }

    func loadMoreItems(
        currentItems: [WithdrawItem],
        latestTotal: Int,
        requestedCount: Int
    ) async throws -> (items: [WithdrawItem], total: Int, requested: Int) {
        guard latestTotal > 0 else {
            return ([], 0, 0)
        }

        var pageControl = buildPageControl(totalNum: latestTotal, requestedCount: requestedCount)
        guard pageControl.isAbleLoadMore else {
            return (currentItems, latestTotal, min(requestedCount, latestTotal))
        }

        let existingIds = Set(currentItems.map(\.id))
        var mergedItems = currentItems
        var nextRequestedCount = requestedCount
        var didAppendNewItem = false

        while pageControl.isAbleLoadMore, !didAppendNewItem {
            let pageResult = try await fetchPage(pageControl: &pageControl)
            nextRequestedCount = min(latestTotal, nextRequestedCount + pageResult.requestedCount)

            let appendedItems = pageResult.items.filter { !existingIds.contains($0.id) }
            if !appendedItems.isEmpty {
                mergedItems = dedupAndSort(items: currentItems + appendedItems)
                didAppendNewItem = true
            }

            if pageResult.requestedCount == 0, !pageControl.isAbleLoadMore {
                break
            }
        }

        return (dedupAndSort(items: mergedItems), latestTotal, nextRequestedCount)
    }

    func fetchPage(pageControl: inout Safe4PageControl) async throws -> (items: [WithdrawItem], requestedCount: Int) {
        guard pageControl.isAbleLoadMore else {
            return ([], 0)
        }

        let ids = try await ids(start: pageControl.start, count: pageControl.currentPageCount).filter { $0 != 0 }
        guard !ids.isEmpty else {
            pageControl.plusPage()
            return ([], 0)
        }

        let infos = try await getRecordInfos(ids: ids)
        let records = try await records(from: infos)
        let pageItems = records.map {
            WithdrawItem(
                type: service.type,
                lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                record: $0.record,
                info: $0.info
            )
        }

        pageControl.plusPage()
        return (pageItems, ids.count)
    }

    func records(from infos: [(web3swift.AccountRecord, RecordUseInfo)]) async throws -> [Safe4WithdrawLockedRecord] {
        switch service.type {
        case .masterNode:
            let tempArray = infos.filter { $0.1.frozenAddr.address != nullAddress }
            let array = await node(nodeType: .masterNode, records: tempArray)
            return array.map {
                Safe4WithdrawLockedRecord(
                    type: .masterNode,
                    record: Safe4AccountRecord(record: $0.0),
                    info: Safe4RecordUseInfo(info: $0.1)
                )
            }
        case .superNode:
            let tempArray = infos.filter { $0.1.frozenAddr.address != nullAddress }
            let array = await node(nodeType: .superNode, records: tempArray)
            return array.map {
                Safe4WithdrawLockedRecord(
                    type: .superNode,
                    record: Safe4AccountRecord(record: $0.0),
                    info: Safe4RecordUseInfo(info: $0.1)
                )
            }
        case .voteLocked:
            let voteArray = infos.filter { $0.1.votedAddr.address != nullAddress }
            return voteArray.map {
                Safe4WithdrawLockedRecord(
                    type: .voteLocked,
                    record: Safe4AccountRecord(record: $0.0),
                    info: Safe4RecordUseInfo(info: $0.1)
                )
            }
        case .proposal:
            let tempArray = infos.filter { $0.1.frozenAddr.address != nullAddress }
            return tempArray.map {
                Safe4WithdrawLockedRecord(
                    type: .proposal,
                    record: Safe4AccountRecord(record: $0.0),
                    info: Safe4RecordUseInfo(info: $0.1)
                )
            }
        }
    }

    func ids(start: Int, count: Int) async throws -> [BigUInt] {
        switch service.type {
        case .masterNode, .superNode:
            return try await service.getAvailableIDs(type: .native, start: BigUInt(start), count: BigUInt(count))
        case .proposal:
            let proposalIds = try await service.mineProposalIds(start: BigUInt(start), count: BigUInt(count))
            return try await mineProposalLockIds(ids: proposalIds)
        case .voteLocked:
            return try await service.getVotedIDs4Voter(start: BigUInt(start), count: BigUInt(count))
        }
    }

    func getRecordInfos(ids: [BigUInt]) async throws -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results = [(web3swift.AccountRecord, RecordUseInfo)]()

        for id in ids {
            if Task.isCancelled { break }
            do {
                let useInfo = try await service.getRecordUseInfo(id: id)
                let info = try await service.getRecordByID(id: id)
                results.append((info, useInfo))
            } catch {}
        }

        return results
    }

    func mineProposalLockIds(ids: [BigUInt]) async throws -> [BigUInt] {
        var lockIds = [BigUInt]()

        for id in ids {
            let rewardIDs = try await service.getProposalRewardIDs(id: id)
            lockIds.append(contentsOf: rewardIDs)
        }

        return lockIds
    }

    func node(
        nodeType: WithdrawViewService.NodeType,
        records: [(web3swift.AccountRecord, RecordUseInfo)]
    ) async -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results = [(web3swift.AccountRecord, RecordUseInfo)]()

        for node in records {
            if Task.isCancelled { break }
            do {
                switch nodeType {
                case .masterNode:
                    let isMaster = try await service.isMasterNodeFounder(node.1.frozenAddr)
                    if isMaster {
                        results.append(node)
                    }
                case .superNode:
                    let isSuper = try await service.isSuperNodeFounder(node.1.frozenAddr)
                    if isSuper {
                        results.append(node)
                    }
                }
            } catch {}
        }

        return results
    }

    func restoreCache() {
        do {
            let records = try withdrawLockedStorage.allRecords(by: service.type.lockedRecordType)
            let items = records.map {
                WithdrawItem(
                    type: service.type,
                    lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                    record: $0.record,
                    info: $0.info
                )
            }

            viewItems = dedupAndSort(items: items)
        } catch {
            viewItems = []
        }

        if let snapshot = restoreCacheSnapshot() {
            cachedTotal = max(snapshot.totalNum, viewItems.count)
            requestedCount = min(max(snapshot.requestedCount, min(viewItems.count, cachedTotal)), cachedTotal)
        } else {
            cachedTotal = viewItems.count
            requestedCount = min(max(viewItems.count, min(Self.pageSize, cachedTotal)), cachedTotal)
        }

        pageControl = buildPageControl(totalNum: cachedTotal, requestedCount: requestedCount)
        hasMoreItems = pageControl.isAbleLoadMore
        dataState = .items
    }

    func apply(items: [WithdrawItem], total: Int, requestedCount: Int) {
        let incomingIds = Set(items.map(\.id))
        viewItems = dedupAndSort(items: items)
        cachedTotal = total
        self.requestedCount = requestedCount
        pageControl = buildPageControl(totalNum: total, requestedCount: requestedCount)
        pendingRemovedIds = pendingRemovedIds.intersection(incomingIds)
        hasMoreItems = pageControl.isAbleLoadMore
        persistCache(items: viewItems, total: total, requestedCount: requestedCount)
        dataState = .items
        selectedItems = selectedItems.filter { item in
            viewItems.contains(where: { $0.id == item.id })
        }
    }

    func applyLocalWithdrawSuccess(items: [WithdrawItem]) {
        let removedIds = Set(items.map(\.id))
        pendingRemovedIds.formUnion(removedIds)
        viewItems.removeAll { removedIds.contains($0.id) }
        viewItems = dedupAndSort(items: viewItems)
        pageControl = buildPageControl(totalNum: cachedTotal, requestedCount: requestedCount)
        hasMoreItems = pageControl.isAbleLoadMore
        persistCache(items: viewItems, total: cachedTotal, requestedCount: requestedCount)
    }

    func persistCache(items: [WithdrawItem], total: Int, requestedCount: Int) {
        let records = items.map { item in
            item.asWithdrawLockedRecord(type: service.type.lockedRecordType)
        }

        do {
            try withdrawLockedStorage.replaceAll(type: service.type.lockedRecordType, records: records)
        } catch {}

        let snapshot = CacheSnapshot(totalNum: total, requestedCount: requestedCount)
        if let data = try? JSONEncoder().encode(snapshot),
           let json = String(data: data, encoding: .utf8)
        {
            userDefaultsStorage.set(value: json, for: cacheSnapshotKey)
        }

        saveCacheTimestamp()
    }

    func restoreCacheSnapshot() -> CacheSnapshot? {
        guard let json: String = userDefaultsStorage.value(for: cacheSnapshotKey),
              let data = json.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(CacheSnapshot.self, from: data)
    }

    func buildPageControl(totalNum: Int, requestedCount: Int) -> Safe4PageControl {
        var pageControl = Safe4PageControl(pageSize: Self.pageSize)
        pageControl.set(totalNum: totalNum)

        guard totalNum > 0, requestedCount > 0 else {
            return pageControl
        }

        let normalizedRequestedCount = min(requestedCount, totalNum)
        let fullPagesLoaded = normalizedRequestedCount / Self.pageSize
        let hasPartialPage = normalizedRequestedCount % Self.pageSize != 0
        let pagesFetched = fullPagesLoaded + (hasPartialPage ? 1 : 0)

        for _ in 0 ..< pagesFetched {
            pageControl.plusPage()
        }

        return pageControl
    }

    func dedupAndSort(items: [WithdrawItem]) -> [WithdrawItem] {
        let filtered = items.filter { !pendingRemovedIds.contains($0.id) }
        var seen = Set<BigUInt>()
        var result = [WithdrawItem]()

        for item in filtered where seen.insert(item.id).inserted {
            result.append(item)
        }

        return result.sorted { Int($0.id) < Int($1.id) }
    }

    func saveCacheTimestamp() {
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheTimestampKey)
    }

    func isCacheExpired(maxAge: TimeInterval) -> Bool {
        guard let timestamp: TimeInterval = userDefaultsStorage.value(for: cacheTimestampKey) else {
            return true
        }
        return Date().timeIntervalSince1970 - timestamp > maxAge
    }

    var cacheTimestampKey: String {
        "\(WithdrawCacheTimestampKey)_\(service.type.rawValue)"
    }

    var cacheSnapshotKey: String {
        "\(WithdrawCacheSnapshotKey)_\(service.type.rawValue)"
    }
}

extension WithdrawViewModel {
    enum RequestError: Error {
        case pageError
        case getInfo
        case withdrawError
    }

    enum SendStatus {
        case normal
        case loading
        case failed(Error)
        case completed
    }

    static func getDidWithdrawIds() -> [String] {
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: WithdrawIdsKey) else { return [] }
        return ids
    }

    static func saveDidWithdrawIds(_ ids: [String]) {
        var oldIds = WithdrawViewModel.getDidWithdrawIds()
        oldIds.append(contentsOf: ids)
        oldIds = Array(Set(oldIds))
        Core.shared.userDefaultsStorage.set(value: oldIds, for: WithdrawIdsKey)
    }

    static func saveRemoveVoteIds(_ ids: [String]) {
        var oldIds = WithdrawViewModel.getRemoveVoteIds()
        oldIds.append(contentsOf: ids)
        oldIds = Array(Set(oldIds))
        Core.shared.userDefaultsStorage.set(value: oldIds, for: RemoveVoteIdsKey)
    }

    static func getRemoveVoteIds() -> [String] {
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: RemoveVoteIdsKey) else { return [] }
        return ids
    }
}

struct WithdrawItem: Equatable, Hashable, Identifiable {
    let id: BigUInt
    let amount: String
    let unlockHeight: BigUInt
    let releaseHeight: BigUInt
    let address: String

    let isWithdrawEnable: Bool
    let isRemoveVoteEnable: Bool
    let record: Safe4AccountRecord
    let info: Safe4RecordUseInfo?

    var idStr: String {
        id.description
    }

    var isSelEnable: Bool {
        isWithdrawEnable || isRemoveVoteEnable
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(type: SafeWithdrawType, lastBlockHeight: BigUInt, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        let releaseHeight = BigUInt(info?.releaseHeight ?? "0") ?? .zero
        let unlockHeight = BigUInt(record.unlockHeight) ?? .zero
        let address = info?.votedAddr ?? ""
        let withdrawEnable =
            (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) ||
            (unlockHeight.isZero && (releaseHeight < lastBlockHeight))
        let removeVoteEnable = type == .voteLocked ? (!releaseHeight.isZero && releaseHeight < lastBlockHeight) : false
        let amount = (BigUInt(record.amount) ?? .zero).safe4FomattedAmount + " SAFE"

        let didWithdrawIds = WithdrawViewModel.getDidWithdrawIds()
        let isWithdraw = didWithdrawIds.contains(record.id.description)

        let didRemoveVoteIds = WithdrawViewModel.getRemoveVoteIds()
        let isRemoveVote = didRemoveVoteIds.contains(record.id.description)

        self.id = BigUInt(record.id)
        self.amount = amount
        self.unlockHeight = BigUInt(unlockHeight)
        self.releaseHeight = releaseHeight
        self.address = address
        self.isWithdrawEnable = withdrawEnable && !isWithdraw
        self.isRemoveVoteEnable = removeVoteEnable && !isRemoveVote
        self.record = record
        self.info = info
    }

    init(
        id: BigUInt,
        amount: String,
        unlockHeight: BigUInt,
        releaseHeight: BigUInt,
        address: String,
        isWithdrawEnable: Bool,
        isRemoveVoteEnable: Bool,
        record: Safe4AccountRecord,
        info: Safe4RecordUseInfo?
    ) {
        self.id = id
        self.amount = amount
        self.unlockHeight = unlockHeight
        self.releaseHeight = releaseHeight
        self.address = address
        self.isWithdrawEnable = isWithdrawEnable
        self.isRemoveVoteEnable = isRemoveVoteEnable
        self.record = record
        self.info = info
    }

    func asWithdrawLockedRecord(type: LockedRecordSourceType) -> Safe4WithdrawLockedRecord {
        Safe4WithdrawLockedRecord(type: type, record: record, info: info)
    }
}

private extension SafeWithdrawType {
    var lockedRecordType: LockedRecordSourceType {
        switch self {
        case .masterNode: return .masterNode
        case .superNode: return .superNode
        case .voteLocked: return .voteLocked
        case .proposal: return .proposal
        }
    }
}
