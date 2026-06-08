import Foundation
import UIKit
import RxSwift
import RxRelay
import RxCocoa
import HsToolKit
import MarketKit
import BigInt
import web3swift
import Web3Core
import HsExtensions

@MainActor
class SuperNodeViewModel: ObservableObject {
    private static let cacheMaxAge: TimeInterval = 120
    private static let pageSize = 10
    private static let pageFetchConcurrency = 10
    private static let partnerAddressesKeyPrefix = "safe4_superNode_partner_addresses"
    private static let cacheOrderKeyPrefix = "safe4_superNode_cache_order"
    let type: SuperNodeModule.SuperNodeType
    private let service: SuperNodeService
    private let disposeBag = DisposeBag()
    private var safe4Page: Safe4PageControl
    private var partnerSafe4Page: Safe4PageControl
    private var partnerAddressArray = [EthereumAddress]()
    private var nodeStorageManager: NodeStorageManager
    private var cachedInfoByAddress = [String: SuperNodeInfo]()
    private var metricsCache = [String: VoteMetrics]()
    private var cachedAllVoteNum: BigUInt?
    private var allRequestTask: Task<Void, Never>?
    private var allRequestId: UUID?
    private var mineRequestTask: Task<Void, Never>?
    private var mineRequestId: UUID?
    private var catchUpTask: Task<Void, Never>?
    private var targetTotalNumForCatchUp: Int?

    private let stateRelay = BehaviorRelay<SuperNodeViewModel.State>(value: .loading)
    private let isLoadingMoreRelay = BehaviorRelay<Bool>(value: false)
    private var viewItems = [SuperNodeViewModel.ViewItem]()
    private var cacheItems = [SuperNodeViewModel.ViewItem]()

    private(set) var state: SuperNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    var address: String {
        service.receiveAddress
    }
    
    init(service: SuperNodeService, type: SuperNodeModule.SuperNodeType) {
        self.service = service
        self.type = type
        let initialSafe4Page = Safe4PageControl(pageSize: Self.pageSize)
        self.safe4Page = initialSafe4Page
        self.partnerSafe4Page = Safe4PageControl(pageSize: Self.pageSize)
        self.nodeStorageManager = NodeStorageManager(nodeType: .superNode, pageControl: initialSafe4Page, scopeKey: type.cacheScopeKey(address: service.receiveAddress))

        subscribe(disposeBag, service.syncRefreshObservable) { [weak self] _ in self?.refresh() }
    }
}

// Mine
extension SuperNodeViewModel {
    
    private func requestMineNodeInfos(loadMore: Bool) {
        guard mineRequestTask == nil else { return }
        if viewItems.isEmpty {
            state = .loading
        }
        if loadMore {
            isLoadingMoreRelay.accept(true)
        }
        let requestId = UUID()
        mineRequestId = requestId
        let task = Task { [service] in
            defer {
                if loadMore {
                    self.isLoadingMoreRelay.accept(false)
                }
                if self.mineRequestId == requestId {
                    self.mineRequestTask = nil
                    self.mineRequestId = nil
                }
            }
            do {
                var partnerAddrs = [Web3Core.EthereumAddress]()
                if !loadMore {
                    let totalNum = try await service.getAddrNum4Creator()
                    guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                    safe4Page.set(totalNum: Int(totalNum))
                    partnerAddrs = try await allPartnerAddrs()
                }
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                guard safe4Page.totalNum > 0 || partnerAddressArray.count > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard loadMore || viewItems.count < safe4Page.totalNum + partnerAddressArray.count else {
                    state = .completed(datas: viewItems)
                    return
                }
                var creatorAddrs = [Web3Core.EthereumAddress]()
                if safe4Page.totalNum > 0 {
                    creatorAddrs = try await service.getAddrs4Creator(page: safe4Page)
                }
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                if creatorAddrs.count > 0 { safe4Page.plusPage() }
                let addrs = partnerAddrs + creatorAddrs
                let sortedResults = await fetchNodeItems(addresses: addrs, isEnabledEdit: true)
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                if !loadMore {
                    viewItems.removeAll()
                }
                mergeInOrder(items: sortedResults)
                saveCurrentCache(pageControl: safe4Page)
                state = .completed(datas: viewItems)
            }catch{
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                if !viewItems.isEmpty {
                    state = .completed(datas: viewItems)
                } else if !cacheItems.isEmpty {
                    viewItems = cacheItems
                    state = .completed(datas: viewItems)
                } else {
                    state = .failed(error: "")
                }
            }
        }
        mineRequestTask = task
    }
    
    private func allPartnerAddrs() async throws -> [Web3Core.EthereumAddress] {
        let totalNum = try await service.getAddrNum4Partner(addr: service.address.address)
        partnerSafe4Page.set(totalNum: Int(totalNum))
        guard partnerSafe4Page.totalNum > 0 else {
            partnerAddressArray = []
            cachePartnerAddresses([])
            return []
        }

        let pages = partnerSafe4Page.pageArray
        var pageResults = Array<[Web3Core.EthereumAddress]?>(repeating: nil, count: pages.count)
        var hadFailure = false
        await withTaskGroup(of: (Int, Result<[Web3Core.EthereumAddress], Error>).self) { taskGroup in
            for (index, page) in pages.enumerated() {
                taskGroup.addTask { [self] in
                    do {
                        let partnerAddrs = try await service.getAddrs4Partner(addr: service.address.address, start: BigUInt(page.first ?? 0), count: BigUInt(page.count))
                        return (index, .success(partnerAddrs))
                    }catch{
                        return (index, .failure(SuperNodeError.getInfo))
                    }
                }
            }

            for await (index, result) in taskGroup {
                switch result {
                case let .success(value):
                    pageResults[index] = value
                case .failure:
                    hadFailure = true
                }
            }
        }

        guard !hadFailure else {
            return partnerAddressArray
        }

        let results = pageResults.compactMap { $0 }.flatMap { $0 }
        partnerAddressArray = results
        cachePartnerAddresses(results.map(\.address))
        return results
    }
}

// All
extension SuperNodeViewModel {
    private func requestInfos(loadMore: Bool, showLoading: Bool = true, resetBeforeLoad: Bool = false, refreshHeadIfNeeded: Bool = false, forcePersistRefreshedCache: Bool = false) {
        guard allRequestTask == nil else { return }
        if showLoading { state = .loading }
        if loadMore {
            isLoadingMoreRelay.accept(true)
        }

        if resetBeforeLoad {
            safe4Page = Safe4PageControl(pageSize: Self.pageSize)
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
        }

        let requestId = UUID()
        allRequestId = requestId
        let task = Task { [service] in
            defer {
                if loadMore {
                    self.isLoadingMoreRelay.accept(false)
                }
                if self.allRequestId == requestId {
                    self.allRequestTask = nil
                    self.allRequestId = nil
                }
            }
            do{
                if !loadMore { let _ = try await allPartnerAddrs() }
                guard self.allRequestId == requestId, !Task.isCancelled else { return }
                let latestTotalNum = try await Int(service.getTotalNum())
                guard self.allRequestId == requestId, !Task.isCancelled else { return }
                reconcileTotal(latestTotalNum: latestTotalNum)

                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }

                if refreshHeadIfNeeded, !loadMore, !viewItems.isEmpty {
                    try await refreshLoadedWindow(totalNum: latestTotalNum, forcePersistCache: forcePersistRefreshedCache)
                    guard self.allRequestId == requestId, !Task.isCancelled else { return }
                    state = .completed(datas: viewItems)
                    return
                }
                guard self.allRequestId == requestId, !Task.isCancelled else { return }

                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }
                let pageStart = safe4Page.start
                let addrs = try await service.superNodeAddressArray(page: safe4Page)
                guard self.allRequestId == requestId, !Task.isCancelled else { return }
                if addrs.count > 0 { safe4Page.plusPage() }
                let sortedResults = await fetchNodeItems(addresses: addrs, isEnabledEdit: false)
                guard self.allRequestId == requestId, !Task.isCancelled else { return }
                mergeInOrder(items: sortedResults, startIndex: pageStart)
                saveCurrentCache(pageControl: safe4Page)
                state = .completed(datas: viewItems)
            }catch{
                guard self.allRequestId == requestId, !Task.isCancelled else { return }
                if viewItems.isEmpty {
                    state = .failed(error: "")
                } else {
                    state = .completed(datas: viewItems)
                }
            }
        }
        allRequestTask = task
    }
}

// search
extension SuperNodeViewModel {
    func search(text: String?) {
        searchCautionRelay.accept(nil)
        guard let text, text.count > 0 else {
            state = .completed(datas: viewItems)
            return
        }
        state = .loading
        Task {
            do {
                if text.contains("0x") {
                    guard service.isValidAddress(text) else {
                        let caution = Caution(text: "safe_zone.super_node.invalid_address".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let address = Web3Core.EthereumAddress(text)!
                    let isExist = try await service.exist(address)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.super_node.address_not_exist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(address: address, isEnabledEdit: false)
                    state = .searchResults(datas: [viewItem])
                    
                }else if let id = BigUInt(text) {
                    let isExist = try await service.existID(id)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.super_node.id_not_exist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "safe_zone.super_node.invalid_id_or_address".localized, type: .error)
                    searchCautionRelay.accept(caution)
                    state = .searchResults(datas: [])
                }
            }catch{
                state = .searchResults(datas: [])
            }
        }
    }
    
    private func nodeInfoBy(id: BigUInt) async throws -> ViewItem {
        let info = try await service.getInfoByID(id)
        return try await nodeInfoBy(address: info.addr, isEnabledEdit: false)
    }
    
    private func nodeInfoBy(address: Web3Core.EthereumAddress, isEnabledEdit: Bool, allVoteNum: BigUInt? = nil) async throws -> ViewItem {
        let info: SuperNodeInfo
        if let cached = cachedInfoByAddress[address.address.lowercased()] {
            info = cached
        } else {
            info = try await service.getInfo(address: address)
            cachedInfoByAddress[address.address.lowercased()] = info
        }
        let cachedMetrics = metricsCache[address.address.lowercased()]
        let metrics = await voteMetrics(address: address, allVoteNum: allVoteNum, fallback: cachedMetrics)

        var ownerType: NodeOwnerType = .None
        
        if info.addr.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Owner
        }
        
        if info.creator.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Creator
        }
        
        if partnerAddressArray.contains(info.addr) {
            ownerType = .Partner
        }
        return ViewItem(info: info, totalVoteNum: metrics.totalVoteNum, totalAmount: metrics.totalAmount, allVoteNum: metrics.allVoteNum, ownerType: ownerType, nodeType: nodeType, isEnabledEdit: isEnabledEdit)
    }
}

extension SuperNodeViewModel {
    func refresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        allRequestId = nil
        mineRequestTask?.cancel()
        mineRequestTask = nil
        mineRequestId = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        targetTotalNumForCatchUp = nil
        viewItems.removeAll()
        restoreCachedPartnerAddresses()
        switch type {
        case .All:
            let hasCache = loadCache()
            let shouldRefreshInBackground = !hasCache || nodeStorageManager.isCacheExpired(maxAge: Self.cacheMaxAge)
            if shouldRefreshInBackground {
                if hasCache {
                    requestInfos(loadMore: false, showLoading: false, resetBeforeLoad: false, refreshHeadIfNeeded: true)
                } else {
                    requestInfos(loadMore: false, showLoading: true, resetBeforeLoad: true)
                }
            } else {
                state = .completed(datas: viewItems)
            }
        case .Mine:
            let hasCache = loadCache()
            if !hasCache {
                cacheItems.removeAll()
                cachedInfoByAddress.removeAll()
                metricsCache.removeAll()
                cachedAllVoteNum = nil
                state = .completed(datas: [])
            }
            requestMineNodeInfos(loadMore: false)
        }
    }

    func softRefresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        allRequestId = nil
        mineRequestTask?.cancel()
        mineRequestTask = nil
        mineRequestId = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        targetTotalNumForCatchUp = nil
        restoreCachedPartnerAddresses()

        switch type {
        case .All:
            requestInfos(loadMore: false, showLoading: viewItems.isEmpty, resetBeforeLoad: false, refreshHeadIfNeeded: true, forcePersistRefreshedCache: true)
        case .Mine:
            requestMineNodeInfos(loadMore: false)
        }
    }
    
    func clearCaches() {
        switch type {
        case .All:
            allRequestTask?.cancel()
            allRequestTask = nil
            allRequestId = nil
            mineRequestTask?.cancel()
            mineRequestTask = nil
            mineRequestId = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
            safe4Page.reset()
            nodeStorageManager.clearCaches()
            cacheItems.removeAll()
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            metricsCache.removeAll()
            cachedAllVoteNum = nil
            refresh()
        case .Mine:
            allRequestTask?.cancel()
            allRequestTask = nil
            allRequestId = nil
            mineRequestTask?.cancel()
            mineRequestTask = nil
            mineRequestId = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
            safe4Page.reset()
            nodeStorageManager.clearCaches()
            cacheItems.removeAll()
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            metricsCache.removeAll()
            cachedAllVoteNum = nil
            cachePartnerAddresses([])
            partnerAddressArray.removeAll()
            refresh()
        }
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        switch type {
        case .All:
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
            guard allRequestTask == nil else { return }
            if safe4Page.isAbleLoadMore && viewItems.count < safe4Page.totalNum {
                requestInfos(loadMore: true, showLoading: false)
            }
        case .Mine:
            guard mineRequestTask == nil else { return }
            guard canLoadMore else { return }
            requestMineNodeInfos(loadMore: true)
        }
    }

    var canLoadMore: Bool {
        switch type {
        case .All:
            return safe4Page.isAbleLoadMore && viewItems.count < safe4Page.totalNum
        case .Mine:
            return safe4Page.isAbleLoadMore && viewItems.count < safe4Page.totalNum + partnerAddressArray.count
        }
    }
    
    func getLockId(viewItem: ViewItem) -> BigUInt? {
        return viewItem.info.founders
            .filter{$0.addr.address.lowercased() == service.address.address.lowercased()}.first?.lockID
    }

    @discardableResult
    private func loadCache() -> Bool {
        guard let snapshot = cacheSnapshot() else {
            return false
        }
            let pageControl = snapshot.pageControl
        let caches = orderedCaches(snapshot.caches)

        let reconstructedItems = deduplicatedByAddress(caches.map {
            let info = $0.transformToSuper()
            let cachedMetrics = cachedMetrics(from: $0)
            return ViewItem(
                info: info,
                totalVoteNum: cachedMetrics?.totalVoteNum ?? 0,
                totalAmount: cachedMetrics?.totalAmount ?? 0,
                allVoteNum: cachedMetrics?.allVoteNum ?? 0,
                ownerType: ownerType(info: info),
                nodeType: nodeType,
                isEnabledEdit: type == .Mine
            )
        })

        let cacheItems: [ViewItem]
        switch type {
        case .All:
            cacheItems = reconstructedItems
        case .Mine:
            guard reconstructedItems.allSatisfy({ $0.ownerType != .None }) else {
                return false
            }
            cacheItems = reconstructedItems
        }

        self.cacheItems = cacheItems
        self.viewItems = cacheItems
        cachedInfoByAddress = Dictionary(uniqueKeysWithValues: cacheItems.map { ($0.info.addr.address.lowercased(), $0.info) })
        metricsCache = Dictionary(uniqueKeysWithValues: cacheItems.map { ($0.info.addr.address.lowercased(), VoteMetrics(totalVoteNum: $0.totalVoteNum, totalAmount: $0.totalAmount, allVoteNum: $0.allVoteNum)) })
        cachedAllVoteNum = cacheItems.compactMap(\.allVoteNum).first(where: { $0 > 0 })
        safe4Page.update(totalNum: pageControl.totalNum, page: pageControl.page, indexPath: pageControl.targetIndexPath)
        state = .completed(datas: viewItems)
        return true
    }

    private func cacheSnapshot() -> (pageControl: Safe4PageControl, caches: [Safe4NodeInfo])? {
        if let snapshot = cacheSnapshot(storageManager: nodeStorageManager) {
            return snapshot
        }

        for fallbackStorageManager in fallbackStorageManagers() {
            if let snapshot = cacheSnapshot(storageManager: fallbackStorageManager) {
                let orderedKeys = orderedCacheKeys(from: snapshot.caches)
                saveCache(pageControl: snapshot.pageControl, infos: snapshot.caches, orderedKeys: orderedKeys)
                return snapshot
            }
        }

        return nil
    }

    private func cacheSnapshot(storageManager: NodeStorageManager) -> (pageControl: Safe4PageControl, caches: [Safe4NodeInfo])? {
        guard let caches = storageManager.load(), !caches.isEmpty else {
            return nil
        }
        let pageControl = storageManager.getPageControl() ?? buildFallbackPageControl(loadedCount: caches.count)
        return (pageControl, caches)
    }

    private func fallbackStorageManagers() -> [NodeStorageManager] {
        switch type {
        case .All:
            return [
                NodeStorageManager(nodeType: .superNode, pageControl: Safe4PageControl(pageSize: Self.pageSize), scopeKey: "all")
            ]
        case .Mine:
            return [
                NodeStorageManager(nodeType: .superNode, pageControl: Safe4PageControl(pageSize: Self.pageSize), scopeKey: nil)
            ]
        }
    }

    private func ownerType(info: SuperNodeInfo) -> NodeOwnerType {
        var ownerType: NodeOwnerType = .None
        if info.addr.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Owner
        }
        if info.creator.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Creator
        }
        if partnerAddressArray.contains(info.addr) {
            ownerType = .Partner
        }
        return ownerType
    }

    private func reconcileTotal(latestTotalNum: Int) {
        let currentTotal = safe4Page.totalNum
        let loadedCount = viewItems.count
        if currentTotal == 0 {
            safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: loadedCount)
            return
        }
        if latestTotalNum == currentTotal {
            return
        }
        if latestTotalNum < currentTotal {
            viewItems.removeAll()
            cacheItems.removeAll()
            cachedInfoByAddress.removeAll()
            metricsCache.removeAll()
            cachedAllVoteNum = nil
            nodeStorageManager.clearCaches()
            safe4Page = Safe4PageControl(pageSize: Self.pageSize)
            safe4Page.set(totalNum: latestTotalNum)
            catchUpTask?.cancel()
            catchUpTask = nil
            return
        }
        safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: loadedCount)
    }

    private func fetchNodeItems(addresses: [Web3Core.EthereumAddress], isEnabledEdit: Bool) async -> [ViewItem] {
        let allVoteNum = await sharedAllVoteNum()
        let cachedInfoSnapshot = cachedInfoByAddress
        let metricsSnapshot = metricsCache
        let partnerAddressSet = Set(partnerAddressArray.map { $0.address.lowercased() })
        let currentAddress = service.address.address.lowercased()
        let creatorAddress = service.receiveAddress.lowercased()
        let nodeTypeSnapshot = nodeType
        var indexedResults = Array<ViewItem?>(repeating: nil, count: addresses.count)
        var fetchedInfoMap = [String: SuperNodeInfo]()
        var fetchedMetricsMap = [String: VoteMetrics]()

        await withTaskGroup(of: (Int, ViewItem?, String?, SuperNodeInfo?, VoteMetrics?).self) { group in
            let initialCount = min(Self.pageFetchConcurrency, addresses.count)
            var nextIndex = 0

            func submitTask(index: Int) {
                let address = addresses[index]
                let cacheKey = address.address.lowercased()
                let cachedInfo = cachedInfoSnapshot[cacheKey]
                let cachedMetrics = metricsSnapshot[cacheKey]

                group.addTask { [service] in
                    if Task.isCancelled {
                        return (index, nil, nil, nil, nil)
                    }

                    let info: SuperNodeInfo?
                    if let cachedInfo {
                        info = cachedInfo
                    } else {
                        info = try? await service.getInfo(address: address)
                    }

                    guard let info else {
                        return (index, nil, nil, nil, nil)
                    }

                    async let totalVoteNumResult = try? service.getTotalVoteNum(address: address)
                    async let totalAmountResult = try? service.getTotalAmount(address: address)

                    let metrics = VoteMetrics(
                        totalVoteNum: await totalVoteNumResult ?? cachedMetrics?.totalVoteNum ?? 0,
                        totalAmount: await totalAmountResult ?? cachedMetrics?.totalAmount ?? 0,
                        allVoteNum: allVoteNum ?? cachedMetrics?.allVoteNum ?? 0
                    )

                    var ownerType: NodeOwnerType = .None
                    if info.addr.address.lowercased() == currentAddress {
                        ownerType = .Owner
                    }
                    if info.creator.address.lowercased() == creatorAddress {
                        ownerType = .Creator
                    }
                    if partnerAddressSet.contains(info.addr.address.lowercased()) {
                        ownerType = .Partner
                    }

                    let item = ViewItem(
                        info: info,
                        totalVoteNum: metrics.totalVoteNum,
                        totalAmount: metrics.totalAmount,
                        allVoteNum: metrics.allVoteNum,
                        ownerType: ownerType,
                        nodeType: nodeTypeSnapshot,
                        isEnabledEdit: isEnabledEdit
                    )

                    return (index, item, cacheKey, info, metrics)
                }
            }

            while nextIndex < initialCount {
                submitTask(index: nextIndex)
                nextIndex += 1
            }

            while let (index, item, cacheKey, info, metrics) = await group.next() {
                if let item {
                    indexedResults[index] = item
                }
                if let cacheKey, let info {
                    fetchedInfoMap[cacheKey] = info
                }
                if let cacheKey, let metrics {
                    fetchedMetricsMap[cacheKey] = metrics
                }

                if nextIndex < addresses.count {
                    submitTask(index: nextIndex)
                    nextIndex += 1
                }
            }
        }

        cachedInfoByAddress.merge(fetchedInfoMap) { _, new in new }
        metricsCache.merge(fetchedMetricsMap) { _, new in new }
        if let refreshedAllVoteNum = fetchedMetricsMap.values.compactMap(\.allVoteNum).first(where: { $0 > 0 }) {
            cachedAllVoteNum = refreshedAllVoteNum
        }

        var results = [ViewItem]()
        var seenIds = Set<String>()
        for item in indexedResults {
            guard let item else { continue }
            if seenIds.insert(item.id).inserted {
                results.append(item)
            }
        }
        return results
    }

    private func buildPageControl(totalNum: Int, loadedCount: Int) -> Safe4PageControl {
        var control = Safe4PageControl(pageSize: Self.pageSize)
        control.set(totalNum: totalNum)
        guard loadedCount > 0 else { return control }
        let lastLoadedIndex = loadedCount - 1
        let nextPage = min((lastLoadedIndex / Self.pageSize) + 1, control.maxPageNum)
        control.update(totalNum: totalNum, page: nextPage, indexPath: IndexPath(row: 0, section: 0))
        return control
    }

    private func buildFallbackPageControl(loadedCount: Int) -> Safe4PageControl {
        guard loadedCount > 0 else {
            return Safe4PageControl(pageSize: Self.pageSize)
        }

        let fallbackTotalNum: Int
        if loadedCount.isMultiple(of: Self.pageSize) {
            fallbackTotalNum = loadedCount + 1
        } else {
            fallbackTotalNum = loadedCount
        }

        return buildPageControl(totalNum: fallbackTotalNum, loadedCount: loadedCount)
    }

    private func refreshLoadedWindow(totalNum: Int, forcePersistCache: Bool = false) async throws {
        let previousLoadedCount = viewItems.count
        let desiredLoadedCount = min(Self.pageSize, totalNum)
        guard desiredLoadedCount > 0 else {
            viewItems.removeAll()
            cacheItems.removeAll()
            cachedInfoByAddress.removeAll()
            metricsCache.removeAll()
            cachedAllVoteNum = nil
            safe4Page = buildPageControl(totalNum: totalNum, loadedCount: 0)
            targetTotalNumForCatchUp = nil
            saveCurrentCache(pageControl: safe4Page)
            return
        }

        var refreshedItems = [ViewItem]()
        var refreshPage = Safe4PageControl(pageSize: Self.pageSize)
        refreshPage.set(totalNum: totalNum)

        while refreshedItems.count < desiredLoadedCount, !Task.isCancelled {
            let addresses = try await service.superNodeAddressArray(page: refreshPage)
            guard !addresses.isEmpty else { break }

            let pageItems = await fetchNodeItems(addresses: addresses, isEnabledEdit: false)
            updateCaches(with: pageItems)
            refreshedItems.append(contentsOf: pageItems)

            if addresses.count > 0 {
                refreshPage.plusPage()
            }

            if !refreshPage.isAbleLoadMore {
                break
            }
        }

        viewItems = deduplicatedByAddress(Array(refreshedItems.prefix(desiredLoadedCount)))
        cacheItems = viewItems
        safe4Page = buildPageControl(totalNum: totalNum, loadedCount: viewItems.count)
        cachedAllVoteNum = viewItems.compactMap(\.allVoteNum).first(where: { $0 > 0 }) ?? cachedAllVoteNum
        if forcePersistCache || shouldPersistRefreshedCache(previousLoadedCount: previousLoadedCount, refreshedCount: viewItems.count, totalNum: totalNum) {
            saveCurrentCache(pageControl: safe4Page)
        }
    }

    private func mergeInOrder(items: [ViewItem], startIndex: Int? = nil) {
        guard !items.isEmpty else { return }
        updateCaches(with: items)

        if let startIndex {
            let identities = Set(items.map(\.cacheIdentity))
            var remainingItems = viewItems.filter { !identities.contains($0.cacheIdentity) }
            let insertionIndex = min(max(startIndex, 0), remainingItems.count)
            remainingItems.insert(contentsOf: items, at: insertionIndex)
            viewItems = deduplicatedByAddress(remainingItems)
        } else {
            for item in items {
                if let existingIndex = viewItems.firstIndex(where: { $0.cacheIdentity == item.cacheIdentity }) {
                    viewItems[existingIndex] = item
                } else {
                    viewItems.append(item)
                }
            }
            viewItems = deduplicatedByAddress(viewItems)
        }
        cacheItems = viewItems
    }

    private func updateCaches(with items: [ViewItem]) {
        for item in items {
            cachedInfoByAddress[item.info.addr.address.lowercased()] = item.info
            metricsCache[item.info.addr.address.lowercased()] = VoteMetrics(totalVoteNum: item.totalVoteNum, totalAmount: item.totalAmount, allVoteNum: item.allVoteNum)
            if item.allVoteNum > 0 {
                cachedAllVoteNum = item.allVoteNum
            }
        }
    }

    private func resolvedViewItem(address: Web3Core.EthereumAddress, isEnabledEdit: Bool, allVoteNum: BigUInt?) async -> ViewItem? {
        if let item = try? await nodeInfoBy(address: address, isEnabledEdit: isEnabledEdit, allVoteNum: allVoteNum) {
            return item
        }

        guard let cachedInfo = cachedInfoByAddress[address.address.lowercased()] else {
            return nil
        }

        let fallbackMetrics = metricsCache[address.address.lowercased()]
        return ViewItem(
            info: cachedInfo,
            totalVoteNum: fallbackMetrics?.totalVoteNum ?? 0,
            totalAmount: fallbackMetrics?.totalAmount ?? 0,
            allVoteNum: allVoteNum ?? fallbackMetrics?.allVoteNum ?? 0,
            ownerType: ownerType(info: cachedInfo),
            nodeType: nodeType,
            isEnabledEdit: isEnabledEdit
        )
    }

    private func cacheRecord(for item: ViewItem) -> Safe4NodeInfo {
        Safe4NodeInfo(
            recordId: 0,
            item.info,
            totalVoteNum: item.totalVoteNum,
            totalAmount: item.totalAmount,
            allVoteNum: item.allVoteNum
        )
    }

    private func saveCurrentCache(pageControl: Safe4PageControl) {
        saveCache(pageControl: pageControl, infos: viewItems.map(cacheRecord(for:)), orderedKeys: viewItems.map(\.cacheIdentity))
    }

    private func saveCache(pageControl: Safe4PageControl, infos: [Safe4NodeInfo], orderedKeys: [String]) {
        nodeStorageManager.save(pageControl: pageControl, infos: infos)
        Core.shared.userDefaultsStorage.set(value: orderedKeys, for: cacheOrderStorageKey)
    }

    private func cachedMetrics(from record: Safe4NodeInfo) -> (totalVoteNum: BigUInt, totalAmount: BigUInt, allVoteNum: BigUInt)? {
        guard
            let totalVoteNumString = record.totalVoteNum,
            let totalAmountString = record.totalAmount,
            let allVoteNumString = record.allVoteNum,
            let totalVoteNum = BigUInt(totalVoteNumString),
            let totalAmount = BigUInt(totalAmountString),
            let allVoteNum = BigUInt(allVoteNumString),
            allVoteNum > 0
        else {
            return nil
        }
        return (totalVoteNum, totalAmount, allVoteNum)
    }

    private func voteMetrics(address: Web3Core.EthereumAddress, allVoteNum: BigUInt?, fallback: VoteMetrics?) async -> VoteMetrics {
        async let totalVoteNumResult = try? service.getTotalVoteNum(address: address)
        async let totalAmountResult = try? service.getTotalAmount(address: address)

        let metrics = VoteMetrics(
            totalVoteNum: await totalVoteNumResult ?? fallback?.totalVoteNum ?? 0,
            totalAmount: await totalAmountResult ?? fallback?.totalAmount ?? 0,
            allVoteNum: allVoteNum ?? fallback?.allVoteNum ?? 0
        )
        metricsCache[address.address.lowercased()] = metrics
        return metrics
    }

    private func sharedAllVoteNum() async -> BigUInt? {
        if let cachedAllVoteNum {
            return cachedAllVoteNum
        }

        if let fetched = try? await service.getAllVoteNum() {
            cachedAllVoteNum = fetched
            return fetched
        }

        let fallback = metricsCache.values.compactMap(\.allVoteNum).first(where: { $0 > 0 })
        cachedAllVoteNum = fallback
        return fallback
    }

    private func deduplicatedByAddress(_ items: [ViewItem]) -> [ViewItem] {
        var seenKeys = Set<String>()
        var results = [ViewItem]()

        for item in items {
            if seenKeys.insert(item.cacheIdentity).inserted {
                results.append(item)
            }
        }

        return results
    }

    private func orderedCaches(_ caches: [Safe4NodeInfo]) -> [Safe4NodeInfo] {
        guard let orderedKeys: [String] = Core.shared.userDefaultsStorage.value(for: cacheOrderStorageKey), !orderedKeys.isEmpty else {
            return cachesByDisplayOrder(caches)
        }

        let cacheMap = Dictionary(uniqueKeysWithValues: caches.map { ($0.addr.lowercased(), $0) })
        let orderedCaches = orderedKeys.compactMap { cacheMap[$0] }
        guard orderedCaches.isEmpty == false else {
            return cachesByDisplayOrder(caches)
        }

        let orderedKeySet = Set(orderedKeys)
        let remainingCaches = cachesByDisplayOrder(caches.filter { !orderedKeySet.contains($0.addr.lowercased()) })
        return orderedCaches + remainingCaches
    }

    private func orderedCacheKeys(from caches: [Safe4NodeInfo]) -> [String] {
        return orderedCaches(caches).map { $0.addr.lowercased() }
    }

    private func cachesByDisplayOrder(_ caches: [Safe4NodeInfo]) -> [Safe4NodeInfo] {
        guard caches.contains(where: { $0.displayOrder != nil }) else {
            return caches
        }

        return caches
            .enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = lhs.element.displayOrder ?? .max
                let rhsOrder = rhs.element.displayOrder ?? .max
                if lhsOrder == rhsOrder {
                    return lhs.offset < rhs.offset
                }
                return lhsOrder < rhsOrder
            }
            .map(\.element)
    }

    private func shouldPersistRefreshedCache(previousLoadedCount: Int, refreshedCount: Int, totalNum: Int) -> Bool {
        guard case .All = type else {
            return true
        }

        if totalNum < previousLoadedCount {
            return true
        }

        return refreshedCount >= previousLoadedCount
    }

    private func cachePartnerAddresses(_ addresses: [String]) {
        Core.shared.userDefaultsStorage.set(value: addresses.map { $0.lowercased() }, for: partnerAddressesStorageKey)
    }

    private func restoreCachedPartnerAddresses() {
        guard let addresses: [String] = Core.shared.userDefaultsStorage.value(for: partnerAddressesStorageKey) else {
            partnerAddressArray = []
            return
        }
        partnerAddressArray = addresses.compactMap(EthereumAddress.init)
    }

    private var partnerAddressesStorageKey: String {
        "\(Self.partnerAddressesKeyPrefix)_\(service.receiveAddress.lowercased())"
    }

    private var cacheOrderStorageKey: String {
        let scope = type == .All ? "all" : "mine_\(service.receiveAddress.lowercased())"
        return "\(Self.cacheOrderKeyPrefix)_\(scope)"
    }
}

extension SuperNodeViewModel {
    struct VoteMetrics {
        let totalVoteNum: BigUInt
        let totalAmount: BigUInt
        let allVoteNum: BigUInt
    }
    
    var stateDriver: Driver<SuperNodeViewModel.State> {
        stateRelay.asDriver()
    }

    var isLoadingMoreDriver: Driver<Bool> {
        isLoadingMoreRelay.asDriver()
    }
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension SuperNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [SuperNodeViewModel.ViewItem])
        case searchResults(datas: [SuperNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        
        let info: SuperNodeInfo
        let totalVoteNum: BigUInt
        let totalAmount: BigUInt
        let allVoteNum: BigUInt

        let ownerType: NodeOwnerType
        let nodeType: Safe4NodeType
        let isEnabledEdit: Bool

        var joinAmount: BigUInt?

        let pledgeNum: BigUInt = 5000
                
        var desc: String {
            info.description
        }
        var id: String {
            info.id.description
        }

        var cacheIdentity: String {
            info.addr.address.lowercased()
        }

        var nodeState: SuperNodeState {
            switch info.state {
            case 0: return .initstate
            case 1: return .online
            case 2: return .abnormal
            default: return .unknown
            }
        }
        
        var rate: Decimal {
            let voteNum = Decimal(bigUInt: totalVoteNum, decimals: safe4Decimals) ?? 0
            guard let allVoteNum = Decimal(bigUInt: allVoteNum, decimals: safe4Decimals), allVoteNum > 0 else { return 0 }
            return (voteNum / allVoteNum)
        }
        
        var foundersTotalAmount: Decimal {
            let total = info.founders.map(\.amount) .reduce(0, +) + (joinAmount ?? 0)
            return Decimal(bigUInt: total, decimals: safe4Decimals) ?? 0
        }
        
        var foundersBalanceAmount: Decimal {
            superNodeRegisterSafeLockNum - foundersTotalAmount
        }
        
        var hasBalance: Bool {
            return foundersTotalAmount < superNodeRegisterSafeLockNum
        }
        
        var isNodeAddress: Bool {
            nodeType != .normal
        }
        
        var isEnabledJoin: Bool {
            hasBalance && !isNodeAddress
        }
        
        var isEnabledVote: Bool {
            nodeType != .superNode && !hasBalance
        }
        
        var isEnabledAddLockDay: Bool {
            ownerType == .Creator || ownerType == .Partner
        }
        
        mutating func update(joinAmount: BigUInt?) {
            self.joinAmount = joinAmount
        }
    }
    
    enum SuperNodeError: Error {
        case getInfo
    }
    
    enum SuperNodeState {
        case initstate
        case online
        case abnormal
        case unknown
        
        var title: String {
            switch self {
            case .initstate:
                "safe_zone.safe4.state.init".localized
            case .online:
                "safe_zone.safe4.state.online".localized
            case .abnormal:
                "safe_zone.safe4.state.abnormal".localized
            case .unknown:
                "safe_zone.safe4.state.unknown".localized
            }
        }
        
        var color: UIColor {
            switch self {
            case .initstate:
                    .themeRemus
            case .online:
                    .themeIssykBlue
            case .abnormal:
                    .themeElena
            case .unknown:
                    .themeElena
            }
        }
    }
    
    enum NodeOwnerType {
        case Owner
        case Creator
        case Partner
        case None
        
        var title: String {
            switch self {
            case .Owner: ""
            case .Creator: "safe_zone.safe4.node.creator".localized
            case .Partner: "safe_zone.safe4.partner".localized
            case .None: ""
            }
        }
    }
}

private extension SuperNodeModule.SuperNodeType {
    func cacheScopeKey(address: String) -> String? {
        switch self {
        case .All:
            nil
        case .Mine:
            "mine_\(address.lowercased())"
        }
    }
}
