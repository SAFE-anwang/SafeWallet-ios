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
class MasterNodeViewModel {
    private let service: MasterNodeService
    private static let cacheMaxAge: TimeInterval = 120
    private static let pageSize = 10
    private var safe4Page = Safe4PageControl(pageSize: 10, isReverse: true)
    private var partnerSafe4Page = Safe4PageControl(pageSize: 10)
    private var nodeStorageManager: NodeStorageManager
    private var cachedInfoByAddress = [String: Safe4NodeInfo]()
    private var allRequestTask: Task<Void, Never>?
    private var mineRequestTask: Task<Void, Never>?
    private var mineRequestId: UUID?
    private var recoveryTask: Task<Void, Never>?
    private var catchUpTask: Task<Void, Never>?
    private var pendingRecoveryAddresses = Set<String>()

    private let stateRelay = BehaviorRelay<MasterNodeViewModel.State>(value: .loading)
    private let isLoadingMoreRelay = BehaviorRelay<Bool>(value: false)
    private var viewItems = [MasterNodeViewModel.ViewItem]()
    private var cacheItems = [MasterNodeViewModel.ViewItem]()
    private var partnerAddressArray = [EthereumAddress]()
    let type: MasterNodeModule.MasterNodeType
    private var targetTotalNumForCatchUp: Int?

    private(set) var state: MasterNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    var address: String {
        service.receiveAddress
    }
    
    init(service: MasterNodeService, type: MasterNodeModule.MasterNodeType) {
        self.service = service
        self.type = type
        self.nodeStorageManager = NodeStorageManager(
            nodeType: .masterNode,
            pageControl: safe4Page,
            scopeKey: type.cacheScopeKey(address: service.receiveAddress)
        )
    }
}

// Mine
extension MasterNodeViewModel {
    
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
        let task = Task { [self, service] in
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
                let addrs = partnerAddrs + creatorAddrs
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask { [self] in
                            do {
                                let item = try await nodeInfoBy(address: address, isEnabledEdit: true)
                                return .success(item)
                            }catch{
                                return .failure(MasterNodeError.getInfo)
                            }
                        }
                    }
                    for await result in taskGroup {
                        switch result {
                        case let .success(value):
                            results.append(value)
                        case let .failure(error):
                            errors.append(error)
                        }
                    }
                }
                results.sort{ Int($0.info.id) > Int($1.info.id) }
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                if results.count > 0 { safe4Page.plusPage() }
                if !loadMore {
                    viewItems.removeAll()
                }
                viewItems.append(contentsOf: results)
                nodeStorageManager.save(
                    pageControl: safe4Page,
                    infos: viewItems.map { Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info) }
                )
                state = .completed(datas: viewItems)
            }catch{
                guard self.mineRequestId == requestId, !Task.isCancelled else { return }
                state = .failed(error: "")
            }
        }
        mineRequestTask = task
    }
    
    private func allPartnerAddrs() async throws -> [Web3Core.EthereumAddress] {
        let totalNum = try await service.getAddrNum4Partner(addr: service.address.address)
        partnerSafe4Page.set(totalNum: Int(totalNum))
        guard partnerSafe4Page.totalNum > 0 else { return [] }
        
        var results: [Web3Core.EthereumAddress] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<[Web3Core.EthereumAddress], Error>.self) { taskGroup in
            for page in partnerSafe4Page.pageArray {
                taskGroup.addTask { [self] in
                    do {
                        let partnerAddrs = try await service.getAddrs4Partner(addr: service.address.address, start: BigUInt(page.first ?? 0), count: BigUInt(page.count))
                        return .success(partnerAddrs)
                    }catch{
                        return .failure(MasterNodeError.getInfo)
                    }
                }
            }
            for await result in taskGroup {
                switch result {
                case let .success(value):
                    results.append(contentsOf: value)
                case let .failure(error):
                    errors.append(error)
                }
            }
        }
        partnerAddressArray = results
        return results
    }
}

// All
extension MasterNodeViewModel {

    private func requestInfos(loadMore: Bool, showLoading: Bool = true, resetBeforeLoad: Bool = false, refreshHeadIfNeeded: Bool = false) {
        guard allRequestTask == nil else { return }

        if showLoading {
            state = .loading
        }
        if loadMore {
            isLoadingMoreRelay.accept(true)
        }

        if resetBeforeLoad {
            safe4Page = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
        }

        allRequestTask = Task { [service] in
            defer {
                if loadMore {
                    self.isLoadingMoreRelay.accept(false)
                }
                Task { @MainActor in self.allRequestTask = nil }
            }

            do{
                async let _ = try allPartnerAddrs()
                let latestTotalNum = try await Int(service.getTotalNum())
                try await reconcileTotalAndCache(latestTotalNum: latestTotalNum, loadMore: loadMore)
                
                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }
                if refreshHeadIfNeeded, !loadMore {
                    try await refreshHeadPage(totalNum: latestTotalNum)
                    state = .completed(datas: viewItems)
                    return
                }
                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }

                let results = try await fetchPageItems(pageControl: safe4Page)

                if results.count > 0 {
                    safe4Page.plusPage()
                }

                for item in results {
                    cachedInfoByAddress[item.info.addr.address.lowercased()] = Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, item.info)
                }
                viewItems.append(contentsOf: results)
                cacheItems = viewItems
                nodeStorageManager.save(
                    pageControl: safe4Page,
                    infos: viewItems.map { Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info) }
                )
                state = .completed(datas: viewItems)
            }catch{
                if viewItems.isEmpty {
                    state = .failed(error: "")
                } else {
                    state = .completed(datas: viewItems)
                }
            }
        }
    }
}

// search
extension MasterNodeViewModel {
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
                        let caution = Caution(text: "safe_zone.safe4.node.address.legal".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let address = Web3Core.EthereumAddress(text)!
                    let isExist = try await service.exist(address)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.node.address.notexist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(address: address, isEnabledEdit: false)
                    state = .searchResults(datas: [viewItem])
                    
                }else if let id = BigUInt(text) {
                    let isExist = try await service.existID(id)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.node.id.notexist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "safe_zone.safe4.node.id.address.input.tips".localized, type: .error)
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
        return ViewItem(info: info, isNodeAddress: nodeType != .normal, isEnabledEdit: false, ownerType: ownerType(info: info))
    }
    
    private func nodeInfoBy(address: Web3Core.EthereumAddress, isEnabledEdit: Bool) async throws -> ViewItem {
        let info = try await service.getInfo(address: address)
        return ViewItem(info: info, isNodeAddress: nodeType != .normal, isEnabledEdit: isEnabledEdit, ownerType: ownerType(info: info))
    }
    
    private func ownerType(info: MasterNodeInfo) -> NodeOwnerType {
        var ownerType: NodeOwnerType = .None
        if info.creator.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Creator
        }else if partnerAddressArray.contains(info.addr) {
            ownerType = .Partner
        }else if info.addr.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Owner
        }
        return ownerType
    }
}

extension MasterNodeViewModel {
    func refresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        mineRequestTask?.cancel()
        mineRequestTask = nil
        mineRequestId = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        targetTotalNumForCatchUp = nil
        pendingRecoveryAddresses.removeAll()

        switch type {
        case .All:
            let hasCache = loadCache()
            let shouldRefreshInBackground = !hasCache || nodeStorageManager.isCacheExpired(maxAge: Self.cacheMaxAge)
            print("[MasterNodeVM] refresh all hasCache=\(hasCache) shouldRefresh=\(shouldRefreshInBackground) viewItems=\(viewItems.count)")
            if shouldRefreshInBackground {
                requestInfos(loadMore: false, showLoading: !hasCache, resetBeforeLoad: !hasCache, refreshHeadIfNeeded: hasCache)
            }else {
                state = .completed(datas: viewItems)
            }
        case .Mine:
            let hasCache = loadCache()
            print("[MasterNodeVM] refresh mine hasCache=\(hasCache) viewItems=\(viewItems.count)")
            requestMineNodeInfos(loadMore: false)
        }
    }

    func softRefresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        mineRequestTask?.cancel()
        mineRequestTask = nil
        mineRequestId = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        targetTotalNumForCatchUp = nil
        pendingRecoveryAddresses.removeAll()

        switch type {
        case .All:
            requestInfos(loadMore: false, showLoading: viewItems.isEmpty, resetBeforeLoad: false, refreshHeadIfNeeded: true)
        case .Mine:
            requestMineNodeInfos(loadMore: false)
        }
    }
    
    func clearCaches() {
        if case .All = type {
            allRequestTask?.cancel()
            allRequestTask = nil
            mineRequestTask?.cancel()
            mineRequestTask = nil
            mineRequestId = nil
            recoveryTask?.cancel()
            recoveryTask = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
            pendingRecoveryAddresses.removeAll()
            safe4Page.reset()
            nodeStorageManager.clearCaches()
            cacheItems.removeAll()
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            refresh()
        }
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        guard allRequestTask == nil else { return }
        switch type {
        case .All:
            if safe4Page.isAbleLoadMore && viewItems.count < safe4Page.totalNum {
                requestInfos(loadMore: true)
            }
    
        case .Mine:
            guard mineRequestTask == nil else { return }
            requestMineNodeInfos(loadMore: true)
        }
    }
    
    func getLockId(viewItem: ViewItem) -> BigUInt? {
        return viewItem.info.founders
            .filter{$0.addr.address.lowercased() == service.address.address.lowercased()}.first?.lockID
    }
    
    @discardableResult
    func loadCache() -> Bool {
        guard let snapshot = cacheSnapshot() else {
            print("[MasterNodeVM] loadCache miss type=\(type)")
            return false
        }
        let pageControl = snapshot.pageControl
        let caches = snapshot.caches

        let cacheItems = caches.map {
            ViewItem(
                info: $0.transformToMaster(),
                isNodeAddress: nodeType != .normal,
                isEnabledEdit: false,
                ownerType: ownerType(info: $0.transformToMaster())
            )
        }

        self.cacheItems = cacheItems
        self.viewItems = cacheItems
        cachedInfoByAddress = Dictionary(uniqueKeysWithValues: caches.map { ($0.addr.lowercased(), $0) })
        safe4Page.update(totalNum: pageControl.totalNum, page: pageControl.page, indexPath: pageControl.targetIndexPath)
        print("[MasterNodeVM] loadCache hit type=\(type) count=\(cacheItems.count) total=\(pageControl.totalNum) page=\(pageControl.page)")
        state = .completed(datas: viewItems)
        return true
    }

    private func cacheSnapshot() -> (pageControl: Safe4PageControl, caches: [Safe4NodeInfo])? {
        if let snapshot = cacheSnapshot(storageManager: nodeStorageManager) {
            print("[MasterNodeVM] cacheSnapshot primary hit type=\(type) count=\(snapshot.caches.count)")
            return snapshot
        }

        for fallbackStorageManager in fallbackStorageManagers() {
            if let snapshot = cacheSnapshot(storageManager: fallbackStorageManager) {
                print("[MasterNodeVM] cacheSnapshot fallback hit type=\(type) count=\(snapshot.caches.count)")
                nodeStorageManager.save(pageControl: snapshot.pageControl, infos: snapshot.caches)
                return snapshot
            }
        }

        print("[MasterNodeVM] cacheSnapshot miss type=\(type)")
        return nil
    }

    private func cacheSnapshot(storageManager: NodeStorageManager) -> (pageControl: Safe4PageControl, caches: [Safe4NodeInfo])? {
        guard let caches = storageManager.load(), !caches.isEmpty else {
            return nil
        }
        let pageControl = storageManager.getPageControl() ?? buildPageControl(totalNum: caches.count, loadedCount: caches.count)
        return (pageControl, caches)
    }

    private func fallbackStorageManagers() -> [NodeStorageManager] {
        switch type {
        case .All:
            return [
                NodeStorageManager(nodeType: .masterNode, pageControl: Safe4PageControl(pageSize: Self.pageSize, isReverse: true), scopeKey: "all")
            ]
        case .Mine:
            return [
                NodeStorageManager(nodeType: .masterNode, pageControl: Safe4PageControl(pageSize: Self.pageSize, isReverse: true), scopeKey: nil)
            ]
        }
    }

    private func reconcileTotalAndCache(latestTotalNum: Int, loadMore: Bool) async throws {
        let currentTotal = safe4Page.totalNum

        if currentTotal == 0 {
            safe4Page.set(totalNum: latestTotalNum)
            return
        }

        if latestTotalNum == currentTotal {
            return
        }

        if latestTotalNum < currentTotal {
            // Chain-side data shrank, invalidate local cache to avoid stale pagination offsets.
            viewItems.removeAll()
            cacheItems.removeAll()
            cachedInfoByAddress.removeAll()
            nodeStorageManager.clearCaches()
            safe4Page = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
            safe4Page.set(totalNum: latestTotalNum)
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
            return
        }

        safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: viewItems.count)
    }

    private func deduplicatedAndSorted(_ items: [ViewItem]) -> [ViewItem] {
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.info.id.description, $0) })
        return Array(map.values).sorted { Int($0.info.id) ?? 0 > Int($1.info.id) ?? 0 }
    }

    private func buildPageControl(totalNum: Int, loadedCount: Int) -> Safe4PageControl {
        var control = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
        control.set(totalNum: totalNum)
        guard loadedCount > 0 else { return control }
        let lastLoadedIndex = loadedCount - 1
        let nextPage = min((lastLoadedIndex / Self.pageSize) + 1, control.maxPageNum)
        control.update(totalNum: totalNum, page: nextPage, indexPath: IndexPath(row: 0, section: 0))
        return control
    }

    private func refreshHeadPage(totalNum: Int) async throws {
        let desiredLoadedCount = min(Self.pageSize, totalNum)
        guard desiredLoadedCount > 0 else {
            viewItems.removeAll()
            cacheItems.removeAll()
            cachedInfoByAddress.removeAll()
            safe4Page = buildPageControl(totalNum: totalNum, loadedCount: 0)
            nodeStorageManager.save(pageControl: safe4Page, infos: [])
            return
        }

        let pageControl = Safe4PageControl(totalNum: totalNum, page: 0, pageSize: desiredLoadedCount, isReverse: true)
        let results = try await fetchPageItems(pageControl: pageControl)

        viewItems = deduplicatedAndSorted(Array(results.prefix(desiredLoadedCount)))
        cacheItems = viewItems
        cachedInfoByAddress = Dictionary(uniqueKeysWithValues: viewItems.map {
            ($0.info.addr.address.lowercased(), Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info))
        })
        safe4Page = buildPageControl(totalNum: totalNum, loadedCount: viewItems.count)
        nodeStorageManager.save(
            pageControl: safe4Page,
            infos: viewItems.map { Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info) }
        )
    }

    private func mergeHeadItems(_ items: [ViewItem], pageControl: Safe4PageControl) {
        guard !items.isEmpty else { return }
        
        for item in items {
            cachedInfoByAddress[item.info.addr.address.lowercased()] = Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, item.info)
        }
        viewItems = deduplicatedAndSorted(items + viewItems)
        cacheItems = viewItems
        nodeStorageManager.save(pageControl: pageControl, infos: viewItems.map { Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info) })
    }

    private func fetchNodeItems(addresses: [Web3Core.EthereumAddress], isEnabledEdit: Bool) async -> ([ViewItem], [Web3Core.EthereumAddress]) {
        var results = [ViewItem]()
        var failed = [Web3Core.EthereumAddress]()

        for address in addresses {
            if Task.isCancelled { break }
            do {
                let item = try await nodeInfoBy(address: address, isEnabledEdit: isEnabledEdit)
                results.append(item)
            } catch {
                failed.append(address)
            }
        }

        return (results, failed)
    }

    private func fetchPageItems(pageControl: Safe4PageControl) async throws -> [ViewItem] {
        let addrs = try await service.masteNodeAddressArray(page: pageControl)
        let cachedSnapshot = cachedInfoByAddress

        var results = [ViewItem]()
        var failedAddrs = [Web3Core.EthereumAddress]()
        let pendingAddrs = addrs.filter { cachedSnapshot[$0.address.lowercased()] == nil }

        for address in addrs {
            let key = address.address.lowercased()
            if let cached = cachedSnapshot[key] {
                let info = cached.transformToMaster()
                results.append(
                    ViewItem(
                        info: info,
                        isNodeAddress: nodeType != .normal,
                        isEnabledEdit: false,
                        ownerType: ownerType(info: info)
                    )
                )
            }
        }

        if !pendingAddrs.isEmpty {
            let fetched = await fetchNodeItems(addresses: pendingAddrs, isEnabledEdit: false)
            results.append(contentsOf: fetched.0)
            failedAddrs = fetched.1
        }

        scheduleRecovery(for: failedAddrs)
        results.sort { Int($0.info.id) > Int($1.info.id) }
        return results
    }

    private func scheduleRecovery(for addresses: [Web3Core.EthereumAddress]) {
        guard !addresses.isEmpty else { return }

        for address in addresses {
            pendingRecoveryAddresses.insert(address.address.lowercased())
        }
        guard recoveryTask == nil else { return }

        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.recoveryTask = nil
                    if !self.pendingRecoveryAddresses.isEmpty {
                        let retryAddresses = self.pendingRecoveryAddresses
                        self.pendingRecoveryAddresses.removeAll()
                        self.scheduleRecovery(for: retryAddresses.compactMap { Web3Core.EthereumAddress($0) })
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 400_000_000)

            let targets = pendingRecoveryAddresses.compactMap { Web3Core.EthereumAddress($0) }
            pendingRecoveryAddresses.removeAll()
            guard !targets.isEmpty else { return }

            var updated = false
            for address in targets {
                if Task.isCancelled { break }
                do {
                    let info = try await service.getInfo(address: address)
                    let record = Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, info)
                    cachedInfoByAddress[address.address.lowercased()] = record

                    if let idx = viewItems.firstIndex(where: { $0.info.addr.address.lowercased() == address.address.lowercased() }) {
                        viewItems[idx] = ViewItem(
                            info: info,
                            isNodeAddress: nodeType != .normal,
                            isEnabledEdit: false,
                            ownerType: ownerType(info: info)
                        )
                    } else {
                        viewItems.append(
                            ViewItem(
                                info: info,
                                isNodeAddress: nodeType != .normal,
                                isEnabledEdit: false,
                                ownerType: ownerType(info: info)
                            )
                        )
                    }
                    updated = true
                } catch {
                    pendingRecoveryAddresses.insert(address.address.lowercased())
                }
            }

            if updated {
                viewItems.sort { Int($0.info.id) ?? 0 > Int($1.info.id) ?? 0 }
                nodeStorageManager.save(
                    pageControl: safe4Page,
                    infos: viewItems.map { Safe4NodeInfo(recordId: NodeStorageType.masterNode.cacheId, $0.info) }
                )
                state = .completed(datas: viewItems)
            }
        }
    }
}

private extension MasterNodeModule.MasterNodeType {
    func cacheScopeKey(address: String) -> String? {
        switch self {
        case .All:
            "all"
        case .Mine:
            "mine_\(address.lowercased())"
        }
    }
}

extension MasterNodeViewModel {
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var stateDriver: Observable<MasterNodeViewModel.State> {
        stateRelay.asObservable()
    }

    var isLoadingMoreDriver: Driver<Bool> {
        isLoadingMoreRelay.asDriver()
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension MasterNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [MasterNodeViewModel.ViewItem])
        case searchResults(datas: [MasterNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        let info: MasterNodeInfo
        let isNodeAddress: Bool
        let isEnabledEdit: Bool
        let ownerType: NodeOwnerType
        var joinAmount: BigUInt?
        
        var id: String {
            info.id.description
        }
        
        var amount: String {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return total.safe4FomattedAmount
        }
        
        var nodeState: MasterNodeState {
            switch info.state {
            case 0: return .initstate
            case 1: return .online
            case 2: return .abnormal
            default: return .unknown
            }
        }
        
        var foundersTotalAmount: Decimal {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return Decimal(bigUInt: total, decimals: safe4Decimals) ?? 0
        }
        
        var foundersBalanceAmount: Decimal {
            masterNodeRegisterSafeLockNum - foundersTotalAmount
        }
        
        var isEnabledJoin: Bool {
            hasBalance && !isNodeAddress
        }
        
        var hasBalance: Bool {
            let total = info.founders.map(\.amount) .reduce(0, +) + (joinAmount ?? 0)
            return Decimal(bigUInt: total, decimals: safe4Decimals)! < masterNodeRegisterSafeLockNum
        }
        
        var isEnabledAddLockDay: Bool {
            ownerType == .Creator || ownerType == .Partner
        }
        
        mutating func update(joinAmount: BigUInt?) {
            self.joinAmount = joinAmount
        }
    }
    
    enum MasterNodeError: Error {
        case getInfo
    }
    
    enum MasterNodeState {
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
