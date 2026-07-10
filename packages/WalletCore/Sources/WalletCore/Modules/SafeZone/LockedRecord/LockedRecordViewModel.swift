import Combine
import UIKit
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

class LockedRecordViewModel: ObservableObject {
    private static let cacheMaxAge: TimeInterval = 120
    private static let withdrawBatchSize = 30
    private static let pageSize = 20
    private static let activeSourceTypes: [LockedRecordSourceType] = [
        .locked,
        .smallAmount01,
        .smallAmount02,
        .voted,
        .proposal,
    ]

    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let service: LockedRecordService
    private let lockedRecoardStorage: Safe4LockedRecordStorage

    private var sourceStatesByType: [LockedRecordSourceType: SourceState]
    private var listTask: Task<Void, Never>?
    private var withdrawTask: Task<Void, Never>?
    private var requestContextId = UUID()
    private var pendingWithdrawRecordKeys = Set<String>()
    private var isLoadingMore = false

    @Published private(set) var dataState: ListState = .items
    @Published private(set) var sendState: WithdrawStatus = .normal
    @Published private(set) var hasMoreItems = true
    @Published private(set) var viewItems: [WithdrawItemRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false

    init(service: LockedRecordService, lockedStorage: Safe4LockedRecordStorage) {
        self.service = service
        self.lockedRecoardStorage = lockedStorage
        self.sourceStatesByType = Self.makeInitialSourceStates()
        restoreCache()
        initialLoad()
    }
}

extension LockedRecordViewModel {
    func withdraw(ids: [BigUInt]) {
        let snapshotItems = viewItems.filter { ids.contains(BigUInt($0.id)) }
        withdraw(items: snapshotItems)
    }

    func withdraw(item: WithdrawItemRecord) {
        withdraw(items: [item])
    }

    @MainActor
    func refresh() async {
        await withCheckedContinuation { continuation in
            if !startRequest(kind: .refresh, onComplete: { continuation.resume() }) {
                continuation.resume()
            }
        }
    }

    func loadMore() {
        _ = startRequest(kind: .loadMore)
    }

    var withdrawEnableIds: [BigUInt] {
        viewItems.filter { $0.withdrawEnable }.map { BigUInt($0.id) }
    }

    var hasWithdrawableItems: Bool {
        viewItems.contains { $0.withdrawEnable }
    }

    func allWithdraw() {
        let items = viewItems.filter { $0.withdrawEnable }
        guard !items.isEmpty else { return }
        guard case .items = dataState else { return }
        withdraw(items: items)
    }
}

private extension LockedRecordViewModel {
    enum RequestKind {
        case initial
        case refresh
        case loadMore
    }

    struct SourceState {
        let sourceType: LockedRecordSourceType
        var items: [WithdrawItemRecord]
        var pageControl: Safe4PageControl
        var cachedTotal: Int
        var latestTotal: Int?
        var requestedCount: Int
        var needsReconcile: Bool
        var isInvalidated: Bool

        var loadedCount: Int {
            items.count
        }
    }

    struct SourcePageSnapshot: Codable {
        let sourceTypeRaw: Int
        let totalNum: Int
        let requestedCount: Int
    }

    struct LockedRecordCacheSnapshot: Codable {
        let sources: [SourcePageSnapshot]
    }

    static func makeInitialSourceStates() -> [LockedRecordSourceType: SourceState] {
        Dictionary(uniqueKeysWithValues: activeSourceTypes.map { sourceType in
            (
                sourceType,
                SourceState(
                    sourceType: sourceType,
                    items: [],
                    pageControl: Safe4PageControl(pageSize: pageSize),
                    cachedTotal: 0,
                    latestTotal: nil,
                    requestedCount: 0,
                    needsReconcile: false,
                    isInvalidated: false
                )
            )
        })
    }

    @discardableResult
    func startRequest(kind: RequestKind, onComplete: (() -> Void)? = nil) -> Bool {
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
            guard listTask == nil, !isRefreshing, !isLoadingMore, hasMoreItems else {
                onComplete?()
                return false
            }
        }

        let requestId = UUID()
        requestContextId = requestId
        isRefreshing = kind == .refresh
        isLoadingMore = kind == .loadMore
        isLoadingNextPage = kind == .loadMore
        dataState = .loading

        let stateSnapshot = sourceStatesByType
        let cacheExpired = isCacheExpired(maxAge: Self.cacheMaxAge)

        listTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.finishRequest(requestId: requestId)
                    onComplete?()
                }
            }

            do {
                let latestTotals = try await fetchLatestTotals()
                let nextStates: [LockedRecordSourceType: SourceState]

                switch kind {
                case .initial:
                    nextStates = try await prepareInitialStates(
                        from: stateSnapshot,
                        latestTotals: latestTotals,
                        cacheExpired: cacheExpired
                    )
                case .refresh:
                    nextStates = try await rebuildStates(
                        from: stateSnapshot,
                        latestTotals: latestTotals
                    )
                case .loadMore:
                    nextStates = try await loadMoreStates(
                        from: stateSnapshot,
                        latestTotals: latestTotals
                    )
                }

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.requestContextId == requestId else { return }
                    self.apply(states: nextStates)
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

    func finishRequest(requestId: UUID) {
        guard requestContextId == requestId else { return }
        listTask = nil
        isRefreshing = false
        isLoadingMore = false
        isLoadingNextPage = false
    }

    func initialLoad() {
        _ = startRequest(kind: .initial)
    }

    func fetchLatestTotals() async throws -> [LockedRecordSourceType: Int] {
        async let nativeTotal = service.totalLockedNum(type: .native)
        async let smallAmount01Total = service.totalLockedNum(type: .smallAmount_01)
        async let smallAmount02Total = service.totalLockedNum(type: .smallAmount_02)
        async let votedTotal = service.getVotedIDNum4Voter()
        async let proposalTotal = service.mineProposalNum()

        return [
            .locked: try await Int(nativeTotal),
            .smallAmount01: try await Int(smallAmount01Total),
            .smallAmount02: try await Int(smallAmount02Total),
            .voted: try await Int(votedTotal),
            .proposal: try await Int(proposalTotal),
        ]
    }

    func prepareInitialStates(
        from currentStates: [LockedRecordSourceType: SourceState],
        latestTotals: [LockedRecordSourceType: Int],
        cacheExpired: Bool
    ) async throws -> [LockedRecordSourceType: SourceState] {
        var nextStates = currentStates

        for sourceType in Self.activeSourceTypes {
            var state = currentStates[sourceType] ?? Self.makeInitialSourceStates()[sourceType]!
            let latestTotal = latestTotals[sourceType] ?? 0
            state.latestTotal = latestTotal

            if latestTotal == 0 {
                state.items = []
                state.cachedTotal = 0
                state.latestTotal = 0
                state.requestedCount = 0
                state.needsReconcile = false
                state.isInvalidated = false
                state.pageControl = buildPageControl(totalNum: 0, requestedCount: 0)
                nextStates[sourceType] = state
                continue
            }

            let shouldReload =
                state.items.isEmpty ||
                cacheExpired ||
                latestTotal != state.cachedTotal ||
                state.needsReconcile ||
                state.isInvalidated

            if shouldReload {
                state = try await rebuildState(state: state, latestTotal: latestTotal)
            } else {
                state.cachedTotal = latestTotal
                state.latestTotal = latestTotal
                state.requestedCount = min(state.requestedCount, latestTotal)
                state.pageControl = buildPageControl(totalNum: latestTotal, requestedCount: state.requestedCount)
                state.needsReconcile = false
                state.isInvalidated = false
            }

            nextStates[sourceType] = state
        }

        return nextStates
    }

    func rebuildStates(
        from currentStates: [LockedRecordSourceType: SourceState],
        latestTotals: [LockedRecordSourceType: Int]
    ) async throws -> [LockedRecordSourceType: SourceState] {
        var nextStates = currentStates

        for sourceType in Self.activeSourceTypes {
            let currentState = currentStates[sourceType] ?? Self.makeInitialSourceStates()[sourceType]!
            let latestTotal = latestTotals[sourceType] ?? 0
            nextStates[sourceType] = try await rebuildState(state: currentState, latestTotal: latestTotal)
        }

        return nextStates
    }

    func loadMoreStates(
        from currentStates: [LockedRecordSourceType: SourceState],
        latestTotals: [LockedRecordSourceType: Int]
    ) async throws -> [LockedRecordSourceType: SourceState] {
        var nextStates = currentStates

        for sourceType in Self.activeSourceTypes {
            var state = currentStates[sourceType] ?? Self.makeInitialSourceStates()[sourceType]!
            let latestTotal = latestTotals[sourceType] ?? 0
            state.latestTotal = latestTotal

            if latestTotal == 0 {
                state.items = []
                state.cachedTotal = 0
                state.requestedCount = 0
                state.needsReconcile = false
                state.isInvalidated = false
                state.pageControl = buildPageControl(totalNum: 0, requestedCount: 0)
                nextStates[sourceType] = state
                continue
            }

            let shouldRebuild = latestTotal != state.cachedTotal || state.needsReconcile || state.isInvalidated
            if shouldRebuild {
                state = try await rebuildState(state: state, latestTotal: latestTotal)
            } else {
                state.cachedTotal = latestTotal
                state.requestedCount = min(state.requestedCount, latestTotal)
                state.pageControl = buildPageControl(totalNum: latestTotal, requestedCount: state.requestedCount)
            }

            if state.pageControl.isAbleLoadMore {
                let pageResult = try await fetchPage(sourceType: sourceType, pageControl: &state.pageControl)
                let pageItems = pageResult.items
                if !pageItems.isEmpty {
                    state.items.append(contentsOf: pageItems)
                    state.items = dedupByCacheKey(items: state.items)
                }
                state.requestedCount = min(state.cachedTotal, state.requestedCount + pageResult.requestedCount)
                state.pageControl = buildPageControl(totalNum: state.cachedTotal, requestedCount: state.requestedCount)
            }

            nextStates[sourceType] = state
        }

        return nextStates
    }

    func rebuildState(state: SourceState, latestTotal: Int) async throws -> SourceState {
        var nextState = state
        nextState.cachedTotal = latestTotal
        nextState.latestTotal = latestTotal
        nextState.needsReconcile = false
        nextState.isInvalidated = false

        guard latestTotal > 0 else {
            nextState.items = []
            nextState.requestedCount = 0
            nextState.pageControl = buildPageControl(totalNum: 0, requestedCount: 0)
            return nextState
        }

        let targetRequestedCount = min(max(state.requestedCount, min(Self.pageSize, latestTotal)), latestTotal)
        var pageControl = Safe4PageControl(pageSize: Self.pageSize)
        pageControl.set(totalNum: latestTotal)
        var fetchedItems = [WithdrawItemRecord]()
        var requestedCount = 0

        while requestedCount < targetRequestedCount, pageControl.isAbleLoadMore {
            let pageResult = try await fetchPage(sourceType: state.sourceType, pageControl: &pageControl)
            let pageItems = pageResult.items
            requestedCount += pageResult.requestedCount
            if pageItems.isEmpty, pageResult.requestedCount == 0, !pageControl.isAbleLoadMore {
                break
            }
            fetchedItems.append(contentsOf: pageItems)
        }

        nextState.items = dedupByCacheKey(items: fetchedItems)
        nextState.requestedCount = min(requestedCount, latestTotal)
        nextState.pageControl = buildPageControl(totalNum: latestTotal, requestedCount: nextState.requestedCount)
        return nextState
    }

    func fetchPage(
        sourceType: LockedRecordSourceType,
        pageControl: inout Safe4PageControl
    ) async throws -> (items: [WithdrawItemRecord], requestedCount: Int) {
        guard pageControl.isAbleLoadMore else { return ([], 0) }

        switch sourceType {
        case .locked:
            let ids = try await service.getLockedIDs(
                type: .native,
                start: BigUInt(pageControl.start),
                count: BigUInt(pageControl.currentPageCount)
            )
            let results = try await getRecordInfos(type: .native, ids: ids)
            if !ids.isEmpty {
                pageControl.plusPage()
            }
            return (buildViewItems(results: results, sourceType: .locked), ids.count)
        case .smallAmount01:
            let ids = try await service.getLockedIDs(
                type: .smallAmount_01,
                start: BigUInt(pageControl.start),
                count: BigUInt(pageControl.currentPageCount)
            )
            let results = try await getRecordInfos(type: .smallAmount_01, ids: ids)
            if !ids.isEmpty {
                pageControl.plusPage()
            }
            return (buildViewItems(results: results, sourceType: .smallAmount01), ids.count)
        case .smallAmount02:
            let ids = try await service.getLockedIDs(
                type: .smallAmount_02,
                start: BigUInt(pageControl.start),
                count: BigUInt(pageControl.currentPageCount)
            )
            let results = try await getRecordInfos(type: .smallAmount_02, ids: ids)
            if !ids.isEmpty {
                pageControl.plusPage()
            }
            return (buildViewItems(results: results, sourceType: .smallAmount02), ids.count)
        case .voted:
            let ids = try await service.getVotedIDs4Voter(
                start: BigUInt(pageControl.start),
                count: BigUInt(pageControl.currentPageCount)
            )
            let results = try await getRecordInfos(type: .native, ids: ids)
            if !ids.isEmpty {
                pageControl.plusPage()
            }
            return (buildViewItems(results: results, sourceType: .voted), ids.count)
        case .proposal:
            let proposalIds = try await service.mineProposalIds(
                start: BigUInt(pageControl.start),
                count: BigUInt(pageControl.currentPageCount)
            )
            let lockIds = try await mineProposalLockIds(ids: proposalIds)
            let results = try await getRecordInfos(type: .native, ids: lockIds)
            if !proposalIds.isEmpty {
                pageControl.plusPage()
            }
            return (
                buildViewItems(
                    results: results.filter { $0.1?.frozenAddr.address != nullAddress },
                    sourceType: .proposal
                ),
                proposalIds.count
            )
        default:
            return ([], 0)
        }
    }

    func apply(states: [LockedRecordSourceType: SourceState]) {
        sourceStatesByType = states
        pendingWithdrawRecordKeys = pendingWithdrawRecordKeys.intersection(allRecordKeys(from: states))
        rebuildViewItems()
        hasMoreItems = canLoadMore(states: states)
        persistCache(states: states)
        dataState = .items
    }

    func persistCache(states: [LockedRecordSourceType: SourceState]) {
        let allRecords = Self.activeSourceTypes
            .compactMap { states[$0] }
            .flatMap(\.items)
            .map { $0.asLockedRecord() }

        do {
            try lockedRecoardStorage.replaceAll(records: allRecords)
        } catch {}

        let snapshots = Self.activeSourceTypes.compactMap { sourceType -> SourcePageSnapshot? in
            guard let state = states[sourceType] else { return nil }
            return SourcePageSnapshot(
                sourceTypeRaw: sourceType.rawValue,
                totalNum: state.cachedTotal,
                requestedCount: state.requestedCount
            )
        }

        if let data = try? JSONEncoder().encode(LockedRecordCacheSnapshot(sources: snapshots)),
           let json = String(data: data, encoding: .utf8)
        {
            userDefaultsStorage.set(value: json, for: cacheSnapshotKey)
        }

        persistCacheTimestamp()
    }

    func restoreCache() {
        var restoredStates = Self.makeInitialSourceStates()
        let pageSnapshotByType = restoreCacheSnapshot()

        do {
            let groupedItems = Dictionary(
                grouping: try lockedRecoardStorage.allRecords().map { item in
                    let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
                    return WithdrawItemRecord(
                        lastBlockHeight: lastBlockHeight,
                        sourceType: item.sourceType,
                        record: item.record,
                        info: item.info
                    )
                },
                by: \.sourceType
            )

            for sourceType in Self.activeSourceTypes {
                guard var state = restoredStates[sourceType] else { continue }
                state.items = dedupByCacheKey(items: groupedItems[sourceType] ?? [])

                let snapshot = pageSnapshotByType[sourceType]
                let totalNum = max(snapshot?.totalNum ?? state.items.count, state.items.count)
                let fallbackRequestedCount = min(max(state.items.count, min(Self.pageSize, totalNum)), totalNum)
                let requestedCount = min(snapshot?.requestedCount ?? fallbackRequestedCount, totalNum)
                state.cachedTotal = totalNum
                state.requestedCount = requestedCount
                state.pageControl = buildPageControl(totalNum: totalNum, requestedCount: state.requestedCount)
                restoredStates[sourceType] = state
            }
        } catch {}

        sourceStatesByType = restoredStates
        rebuildViewItems()
        hasMoreItems = canLoadMore(states: restoredStates)
        dataState = .items
    }

    func restoreCacheSnapshot() -> [LockedRecordSourceType: SourcePageSnapshot] {
        guard let json: String = userDefaultsStorage.value(for: cacheSnapshotKey),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(LockedRecordCacheSnapshot.self, from: data)
        else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: snapshot.sources.compactMap { sourceSnapshot in
            guard let sourceType = LockedRecordSourceType(rawValue: sourceSnapshot.sourceTypeRaw) else {
                return nil
            }
            return (sourceType, sourceSnapshot)
        })
    }

    func rebuildViewItems() {
        let mergedItems = Self.activeSourceTypes
            .compactMap { sourceStatesByType[$0] }
            .flatMap(\.items)

        let filteredItems = mergedItems.filter { !pendingWithdrawRecordKeys.contains($0.recordKey) }
        viewItems = dedupByRecordKey(items: filteredItems)
        sortItems()
    }

    func allRecordKeys(from states: [LockedRecordSourceType: SourceState]) -> Set<String> {
        Set(
            Self.activeSourceTypes
                .compactMap { states[$0] }
                .flatMap(\.items)
                .map(\.recordKey)
        )
    }

    func canLoadMore(states: [LockedRecordSourceType: SourceState]) -> Bool {
        Self.activeSourceTypes.contains { sourceType in
            guard let state = states[sourceType] else { return false }
            return state.pageControl.isAbleLoadMore || state.needsReconcile
        }
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

    func sortItems() {
        viewItems.sort {
            switch ($0.withdrawEnable, $1.withdrawEnable) {
            case (false, false): return Int($0.id) < Int($1.id)
            case (false, true): return false
            case (true, false): return true
            case (true, true): return Int($0.id) < Int($1.id)
            }
        }
    }

    func dedupByRecordKey(items: [WithdrawItemRecord]) -> [WithdrawItemRecord] {
        var seen = Set<String>()
        var result = [WithdrawItemRecord]()
        result.reserveCapacity(items.count)

        for item in items {
            if seen.insert(item.recordKey).inserted {
                result.append(item)
            }
        }

        return result
    }

    func dedupByCacheKey(items: [WithdrawItemRecord]) -> [WithdrawItemRecord] {
        var seen = Set<String>()
        var result = [WithdrawItemRecord]()
        result.reserveCapacity(items.count)

        for item in items {
            if seen.insert(item.cacheKey).inserted {
                result.append(item)
            }
        }

        return result
    }

    private func withdraw(items: [WithdrawItemRecord]) {
        guard withdrawTask == nil else { return }
        guard !items.isEmpty else { return }

        sendState = .loading
        let snapshotItems = items

        withdrawTask = Task { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor in
                    self.withdrawTask = nil
                }
            }

            do {
                let smallAmount01Ids = snapshotItems
                    .filter { $0.sourceType == .smallAmount01 }
                    .map { BigUInt($0.id) }
                let smallAmount02Ids = snapshotItems
                    .filter { $0.sourceType == .smallAmount02 }
                    .map { BigUInt($0.id) }
                let nativeIds = snapshotItems
                    .filter {
                        switch $0.sourceType {
                        case .smallAmount01, .smallAmount02:
                            return false
                        default:
                            return true
                        }
                    }
                    .map { BigUInt($0.id) }

                for chunk in smallAmount01Ids.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .smallAmount_01, ids: chunk)
                }

                for chunk in smallAmount02Ids.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .smallAmount_02, ids: chunk)
                }

                for chunk in nativeIds.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .native, ids: chunk)
                }

                await MainActor.run {
                    applyLocalWithdrawSuccess(items: snapshotItems)
                    LockedRecordViewModel.saveDidWithdrawIds(snapshotItems.map { $0.id.description })
                    sendState = .success(message: "safe_zone.safe4.withdraw".localized + "transactions.types.outgoing".localized)
                }
            } catch {
                await MainActor.run {
                    sendState = .failed(error: "settings.personal_support.failed".localized)
                }
            }
        }
    }

    func applyLocalWithdrawSuccess(items: [WithdrawItemRecord]) {
        let withdrawnKeys = Set(items.map(\.recordKey))
        pendingWithdrawRecordKeys.formUnion(withdrawnKeys)

        for sourceType in Self.activeSourceTypes {
            guard var state = sourceStatesByType[sourceType] else { continue }
            let beforeCount = state.items.count
            state.items.removeAll { withdrawnKeys.contains($0.recordKey) }
            let removedCount = beforeCount - state.items.count

            guard removedCount > 0 else { continue }

            state.latestTotal = nil
            state.needsReconcile = true
            state.requestedCount = min(state.requestedCount, max(state.items.count, min(Self.pageSize, state.cachedTotal)))
            state.pageControl = buildPageControl(totalNum: state.cachedTotal, requestedCount: state.requestedCount)
            sourceStatesByType[sourceType] = state
        }

        rebuildViewItems()
        hasMoreItems = canLoadMore(states: sourceStatesByType)
        persistCache(states: sourceStatesByType)
    }

    func buildViewItems(
        results: [(web3swift.AccountRecord, RecordUseInfo?)],
        sourceType: LockedRecordSourceType
    ) -> [WithdrawItemRecord] {
        results
            .filter { $0.0.id != 0 }
            .map { recordItem, userInfo in
                let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
                let record = Safe4AccountRecord(record: recordItem)
                let info = userInfo.map { Safe4RecordUseInfo(info: $0) }

                return WithdrawItemRecord(
                    lastBlockHeight: lastBlockHeight,
                    sourceType: sourceType,
                    record: record,
                    info: info
                )
            }
    }

    func getRecordInfos(
        type: web3swift.AccountManager.ContractType,
        ids: [BigUInt]
    ) async throws -> [(web3swift.AccountRecord, RecordUseInfo?)] {
        var results = [(web3swift.AccountRecord, RecordUseInfo?)]()

        for id in ids {
            do {
                let info = try await service.getRecordByID(type: type, id: id)
                var useInfo: RecordUseInfo?

                if case .native = type {
                    useInfo = try await service.getRecordUseInfo(type: type, id: id)
                }

                results.append((info, useInfo))
            } catch {
                continue
            }
        }

        return results
    }

    func mineProposalLockIds(ids: [BigUInt]) async throws -> [BigUInt] {
        var lockIds = [BigUInt]()

        for id in ids {
            let rewardIds = try await service.getProposalRewardIDs(id: id)
            lockIds.append(contentsOf: rewardIds)
        }

        return lockIds
    }

    var cacheTimestampKey: String {
        "\(LockedRecordCacheTimestampKey)_\(service.userAddress.address.lowercased())"
    }

    var cacheSnapshotKey: String {
        "\(LockedRecordCacheSnapshotKey)_\(service.userAddress.address.lowercased())"
    }

    func persistCacheTimestamp(_ timestamp: TimeInterval = Date().timeIntervalSince1970) {
        userDefaultsStorage.set(value: timestamp, for: cacheTimestampKey)
    }

    func isCacheExpired(maxAge: TimeInterval) -> Bool {
        guard let timestamp: TimeInterval = userDefaultsStorage.value(for: cacheTimestampKey) else {
            return true
        }

        return Date().timeIntervalSince1970 - timestamp > maxAge
    }
}

extension LockedRecordViewModel {
    enum RequestError: Error {
        case pageError
        case getInfo
        case withdrawError
    }

    enum WithdrawStatus: Equatable {
        case normal
        case loading
        case success(message: String?)
        case failed(error: String?)

        static func == (lhs: WithdrawStatus, rhs: WithdrawStatus) -> Bool {
            switch (lhs, rhs) {
            case (.normal, .normal): return true
            case (.loading, .loading): return true
            case let (.success(lhsMsg), .success(rhsMsg)):
                return lhsMsg == rhsMsg
            case let (.failed(lhsError), .failed(rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    enum LockedRecordItemAction: Hashable, Identifiable {
        case withdraw(id: BigUInt)

        var id: Self {
            self
        }
    }

    static func getDidWithdrawIds() -> [String] {
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: LockedRecordWithdrawIdsKey) else {
            return []
        }

        return ids
    }

    static func saveDidWithdrawIds(_ ids: [String]) {
        var oldIds = LockedRecordViewModel.getDidWithdrawIds()
        oldIds.append(contentsOf: ids)
        oldIds = Array(Set(oldIds))
        Core.shared.userDefaultsStorage.set(value: oldIds, for: LockedRecordWithdrawIdsKey)
    }
}

private let LockedRecordWithdrawIdsKey = "safe4_LockedRecord_WithdrawIds_key"
private let LockedRecordCacheTimestampKey = "safe4_locked_record_cache_timestamp_key"
private let LockedRecordCacheSnapshotKey = "safe4_locked_record_cache_snapshot_key"

extension Sequence {
    func sorted(by first: (Element, Element) -> Bool, _ others: ((Element, Element) -> Bool)...) -> [Element] {
        sorted { a, b in
            if first(a, b) { return true }
            if first(b, a) { return false }

            for order in others {
                if order(a, b) { return true }
                if order(b, a) { return false }
            }

            return false
        }
    }
}

class WithdrawItemRecord: Identifiable, Hashable {
    private let nullAddress = "0x0000000000000000000000000000000000000000"

    let id: Int
    let sourceType: LockedRecordSourceType
    let amount: String
    let unlockHeight: Int
    let releaseHeight: Int?
    let address: String?
    let withdrawEnable: Bool
    let addLockDayEnable: Bool
    let record: Safe4AccountRecord
    let info: Safe4RecordUseInfo?

    var idStr: String {
        id.description
    }

    var cacheKey: String {
        "\(sourceType.rawValue)_\(id)"
    }

    var recordKey: String {
        "\(recordNamespace.rawValue)_\(id)"
    }

    private var recordNamespace: RecordNamespace {
        switch sourceType {
        case .smallAmount01:
            return .smallAmount01
        case .smallAmount02:
            return .smallAmount02
        default:
            return .native
        }
    }

    init(lastBlockHeight: BigUInt, sourceType: LockedRecordSourceType, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        let releaseHeight = BigUInt(info?.releaseHeight ?? "0") ?? .zero
        let unlockHeight = BigUInt(record.unlockHeight) ?? .zero
        let votedAddress = info?.votedAddr ?? nullAddress
        let withdrawEnable =
            (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) ||
            (unlockHeight.isZero && (releaseHeight < lastBlockHeight))
        let addLockDayEnable = (record.type != 0 || votedAddress == nullAddress) ? false : unlockHeight > 0
        let amount = (BigUInt(record.amount) ?? .zero).safe4FomattedAmount + " SAFE"

        let didWithdrawIds = LockedRecordViewModel.getDidWithdrawIds()
        let isWithdraw = didWithdrawIds.contains(record.id.description)

        self.id = record.id
        self.sourceType = sourceType
        self.amount = amount
        self.unlockHeight = Int(unlockHeight)
        self.releaseHeight = releaseHeight.isZero ? nil : Int(releaseHeight)
        self.address = votedAddress == nullAddress ? nil : votedAddress
        self.withdrawEnable = withdrawEnable && !isWithdraw
        self.addLockDayEnable = addLockDayEnable
        self.record = record
        self.info = info
    }

    init(
        id: Int,
        sourceType: LockedRecordSourceType,
        amount: String,
        unlockHeight: Int,
        releaseHeight: Int?,
        address: String?,
        withdrawEnable: Bool,
        addLockDayEnable: Bool,
        record: Safe4AccountRecord,
        info: Safe4RecordUseInfo?
    ) {
        self.id = id
        self.sourceType = sourceType
        self.amount = amount
        self.unlockHeight = unlockHeight
        self.releaseHeight = releaseHeight
        self.address = address
        self.withdrawEnable = withdrawEnable
        self.addLockDayEnable = addLockDayEnable
        self.record = record
        self.info = info
    }

    static func == (lhs: WithdrawItemRecord, rhs: WithdrawItemRecord) -> Bool {
        lhs.id == rhs.id &&
            lhs.recordNamespace == rhs.recordNamespace &&
            lhs.amount == rhs.amount &&
            lhs.unlockHeight == rhs.unlockHeight &&
            lhs.releaseHeight == rhs.releaseHeight &&
            lhs.address == rhs.address
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(recordNamespace.rawValue)
        hasher.combine(amount)
        hasher.combine(unlockHeight)
        hasher.combine(releaseHeight)
        hasher.combine(address)
    }

    func asLockedRecord() -> Safe4LockedRecord {
        Safe4LockedRecord(type: sourceType, record: record, info: info)
    }
}

private enum RecordNamespace: Int {
    case native
    case smallAmount01
    case smallAmount02
}
