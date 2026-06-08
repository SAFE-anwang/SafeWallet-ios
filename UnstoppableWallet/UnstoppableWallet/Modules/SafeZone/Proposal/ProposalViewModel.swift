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
class ProposalViewModel {
    private static let pageSize = 20
    private static let cacheMaxAge: TimeInterval = 120
    let service: ProposalService
    private var safe4Page = Safe4PageControl(pageSize: 20, isReverse: true)
    private var stateRelay = PublishRelay<ProposalViewModel.State>()
    private var viewItems = [ProposalViewModel.ViewItem]()
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)
    let proposalStorageManager: ProposalStorageManager
    private var allRequestTask: Task<Void, Never>?
    private var catchUpTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var requestContextId: UUID?
    private var targetTotalNumForCatchUp: Int?
    private var cachedInfoById = [String: ProposalInfo]()
    private var pendingRecoveryIds = Set<String>()
    @Published var hasNewProposal: Bool = false

    private(set) var state: ProposalViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(service: ProposalService) {
        self.service = service
        self.proposalStorageManager = ProposalStorageManager()
    }
}

extension ProposalViewModel {
    private func isActive(requestId: UUID) -> Bool {
        requestContextId == requestId && !Task.isCancelled
    }

    private func requestInfos(loadMore: Bool, completed: (()-> Void)?) {
        guard allRequestTask == nil else { return }
        catchUpTask?.cancel()
        catchUpTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        state = .loading
        let requestId = UUID()
        requestContextId = requestId
        allRequestTask = Task(priority: .userInitiated) { [service] in
            defer {
                Task { @MainActor in
                    if self.requestContextId == requestId {
                        self.allRequestTask = nil
                        self.startBackgroundCatchUpIfNeeded()
                    }
                }
            }
            do{
                let totalNum = try await service.getTotalNum()
                guard self.isActive(requestId: requestId) else { return }
                reconcileTotal(latestTotalNum: totalNum)
                guard self.isActive(requestId: requestId) else { return }
                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }

                let ids = try await service.proposalIds(offset: proposalOffset(pageControl: safe4Page), count: proposalCount(pageControl: safe4Page))
                guard self.isActive(requestId: requestId) else { return }
                let cachedInfoSnapshot = cachedInfoById
                var fetchedInfoById = [String: ProposalInfo]()
                var results: [ViewItem] = []
                var failedIds = [BigUInt]()
                for id in ids {
                    guard self.isActive(requestId: requestId) else { return }
                    let key = id.description
                    if let cached = fetchedInfoById[key] ?? cachedInfoSnapshot[key] {
                        results.append(ViewItem(info: cached))
                        continue
                    }
                    do {
                        let info = try await service.getInfo(id: id)
                        guard self.isActive(requestId: requestId) else { return }
                        fetchedInfoById[key] = info
                        results.append(ViewItem(info: info))
                    } catch {
                        guard self.isActive(requestId: requestId) else { return }
                        failedIds.append(id)
                    }
                }
                guard self.isActive(requestId: requestId) else { return }
                results.sort{ Int($0.info.id) > Int($1.info.id) }
                cachedInfoById.merge(fetchedInfoById) { _, new in new }
                scheduleRecovery(for: failedIds)
                if results.count > 0 { safe4Page.plusPage() }
                mergeInOrder(items: results)
                self.proposalStorageManager.save(infos: viewItems.map { ProposalInfoRecord(info: $0.info) })
                self.proposalStorageManager.savePageControl(safe4Page)
                state = .completed(datas: viewItems)
                completed?()
            }catch{
                guard self.isActive(requestId: requestId) else { return }
                if viewItems.isEmpty {
                    state = .failed(error: error.localizedDescription)
                } else {
                    state = .completed(datas: viewItems)
                }
            }
        }
    }

    private func requestSoftRefresh() {
        guard allRequestTask == nil else { return }
        catchUpTask?.cancel()
        catchUpTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        state = .loading

        let preservedItems = viewItems
        let preservedPage = safe4Page
        let cachedInfoSnapshot = cachedInfoById
        let requestId = UUID()
        requestContextId = requestId

        allRequestTask = Task(priority: .userInitiated) { [service] in
            defer {
                Task { @MainActor in
                    if self.requestContextId == requestId {
                        self.allRequestTask = nil
                    }
                }
            }

            do {
                let totalNum = try await service.getTotalNum()
                guard self.isActive(requestId: requestId) else { return }
                let loadedWindowCount = max(viewItems.count, proposalOffset(pageControl: preservedPage))
                let desiredLoadedCount = min(totalNum, max(loadedWindowCount, Self.pageSize))

                guard desiredLoadedCount > 0 else {
                    viewItems.removeAll()
                    cachedInfoById.removeAll()
                    proposalStorageManager.clearCaches()
                    safe4Page = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
                    safe4Page.set(totalNum: totalNum)
                    targetTotalNumForCatchUp = nil
                    pendingRecoveryIds.removeAll()
                    state = .completed(datas: [])
                    return
                }

                let ids = try await service.proposalIds(offset: 0, count: desiredLoadedCount)
                guard self.isActive(requestId: requestId) else { return }
                var fetchedInfoById = [String: ProposalInfo]()
                var results = [ViewItem]()
                var failedIds = [BigUInt]()

                for id in ids {
                    guard self.isActive(requestId: requestId) else { return }

                    let key = id.description
                    if let cached = fetchedInfoById[key] {
                        results.append(ViewItem(info: cached))
                        continue
                    }
                    do {
                        let info = try await service.getInfo(id: id)
                        guard self.isActive(requestId: requestId) else { return }
                        fetchedInfoById[key] = info
                        results.append(ViewItem(info: info))
                    } catch {
                        guard self.isActive(requestId: requestId) else { return }
                        if let cached = cachedInfoSnapshot[key] {
                            results.append(ViewItem(info: cached))
                        } else {
                            failedIds.append(id)
                        }
                    }
                }

                guard self.isActive(requestId: requestId) else { return }
                if results.count < min(desiredLoadedCount, preservedItems.count) {
                    var existingIds = Set(results.map(\.id))
                    for item in preservedItems where !existingIds.contains(item.id) {
                        results.append(item)
                        existingIds.insert(item.id)
                        if results.count >= desiredLoadedCount {
                            break
                        }
                    }
                }
                results.sort { Int($0.info.id) > Int($1.info.id) }
                if results.count > desiredLoadedCount {
                    results = Array(results.prefix(desiredLoadedCount))
                }
                cachedInfoById.merge(fetchedInfoById) { _, new in new }
                scheduleRecovery(for: failedIds)

                viewItems = results
                safe4Page = buildPageControl(totalNum: totalNum, loadedCount: desiredLoadedCount)
                targetTotalNumForCatchUp = nil
                proposalStorageManager.save(infos: viewItems.map { ProposalInfoRecord(info: $0.info) })
                proposalStorageManager.savePageControl(safe4Page)
                state = .completed(datas: viewItems)
            } catch {
                guard self.isActive(requestId: requestId) else { return }
                viewItems = preservedItems
                safe4Page = preservedPage
                if preservedItems.isEmpty {
                    state = .failed(error: error.localizedDescription)
                } else {
                    state = .completed(datas: preservedItems)
                }
            }
        }
    }
    
    func loadCache() {
        guard let pageControl = proposalStorageManager.getPageControl() else { return }
        var caches = proposalStorageManager.loadCaches().map{ViewItem(info: $0.transform())}
        caches.sort{ Int($0.info.id) > Int($1.info.id) }
        viewItems = caches
        cachedInfoById = Dictionary(uniqueKeysWithValues: caches.map { ($0.info.id.description, $0.info) })
        safe4Page = pageControl
        state = .completed(datas: viewItems)
    }
    
    func clearCaches() {
        allRequestTask?.cancel()
        allRequestTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        targetTotalNumForCatchUp = nil
        cachedInfoById.removeAll()
        pendingRecoveryIds.removeAll()
        proposalStorageManager.clearCaches()
        viewItems.removeAll()
        safe4Page = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
        refresh()
    }

    private func reconcileTotal(latestTotalNum: Int) {
        let currentTotal = safe4Page.totalNum
        let loadedCount = viewItems.count
        if currentTotal == 0 {
            safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: loadedCount)
            targetTotalNumForCatchUp = nil
            return
        }
        if latestTotalNum == currentTotal {
            return
        }
        if latestTotalNum < currentTotal {
            // when chain shrinks, invalidate cache to keep pagination offsets valid
            cachedInfoById.removeAll()
            viewItems.removeAll()
            proposalStorageManager.clearCaches()
            safe4Page = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
            safe4Page.set(totalNum: latestTotalNum)
            targetTotalNumForCatchUp = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            recoveryTask?.cancel()
            recoveryTask = nil
            pendingRecoveryIds.removeAll()
            return
        }
        safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: loadedCount)
        targetTotalNumForCatchUp = latestTotalNum
    }

    private func buildPageControl(totalNum: Int, loadedCount: Int) -> Safe4PageControl {
        var control = Safe4PageControl(pageSize: Self.pageSize, isReverse: true)
        control.set(totalNum: totalNum)
        guard loadedCount > 0 else { return control }
        let pagesLoaded = Int(ceil(Double(loadedCount) / Double(Self.pageSize)))
        if pagesLoaded > 0 {
            for _ in 0..<pagesLoaded {
                control.plusPage()
            }
        }
        return control
    }

    private func startBackgroundCatchUpIfNeeded() {
        guard case .All = service.type else { return }
        guard catchUpTask == nil else { return }
        guard let requestId = requestContextId else { return }
        guard let targetTotal = targetTotalNumForCatchUp else { return }
        guard viewItems.count < targetTotal else {
            targetTotalNumForCatchUp = nil
            return
        }
        guard allRequestTask == nil else { return }

        catchUpTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    if self.requestContextId == requestId {
                        self.catchUpTask = nil
                        self.startBackgroundCatchUpIfNeeded()
                    }
                }
            }

            while !Task.isCancelled {
                guard self.isActive(requestId: requestId) else { return }
                guard let targetTotal = targetTotalNumForCatchUp else { break }
                if viewItems.count >= targetTotal {
                    targetTotalNumForCatchUp = nil
                    break
                }
                if allRequestTask != nil { break }
                guard safe4Page.isAbleLoadMore else { break }

                do {
                    let ids = try await service.proposalIds(offset: proposalOffset(pageControl: safe4Page), count: proposalCount(pageControl: safe4Page))
                    guard self.isActive(requestId: requestId) else { return }
                    guard !ids.isEmpty else { break }

                    let cachedInfoSnapshot = cachedInfoById
                    var fetchedInfoById = [String: ProposalInfo]()
                    var items = [ViewItem]()
                    var failedIds = [BigUInt]()
                    for id in ids {
                        guard self.isActive(requestId: requestId) else { return }
                        let key = id.description
                        if let cached = fetchedInfoById[key] ?? cachedInfoSnapshot[key] {
                            items.append(ViewItem(info: cached))
                            continue
                        }
                        do {
                            let info = try await service.getInfo(id: id)
                            guard self.isActive(requestId: requestId) else { return }
                            fetchedInfoById[key] = info
                            items.append(ViewItem(info: info))
                        } catch {
                            guard self.isActive(requestId: requestId) else { return }
                            failedIds.append(id)
                        }
                    }

                    guard self.isActive(requestId: requestId) else { return }
                    safe4Page.plusPage()
                    cachedInfoById.merge(fetchedInfoById) { _, new in new }
                    scheduleRecovery(for: failedIds)
                    mergeInOrder(items: items)
                    proposalStorageManager.save(infos: viewItems.map { ProposalInfoRecord(info: $0.info) })
                    proposalStorageManager.savePageControl(safe4Page)
                    state = .completed(datas: viewItems)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    guard self.isActive(requestId: requestId) else { return }
                    break
                }
            }
        }
    }

    private func mergeInOrder(items: [ViewItem]) {
        guard !items.isEmpty else { return }
        var existingIds = Set(viewItems.map(\.id))
        for item in items {
            guard !existingIds.contains(item.id) else { continue }
            existingIds.insert(item.id)
            viewItems.append(item)
            cachedInfoById[item.id] = item.info
        }
        viewItems.sort { Int($0.info.id) > Int($1.info.id) }
    }

    private func proposalOffset(pageControl: Safe4PageControl) -> Int {
        pageControl.page * Self.pageSize
    }

    private func proposalCount(pageControl: Safe4PageControl) -> Int {
        let remaining = max(pageControl.totalNum - proposalOffset(pageControl: pageControl), 0)
        return min(Self.pageSize, remaining)
    }

    private func scheduleRecovery(for ids: [BigUInt]) {
        guard !ids.isEmpty else { return }
        guard let requestId = requestContextId else { return }

        for id in ids {
            pendingRecoveryIds.insert(id.description)
        }
        guard recoveryTask == nil else { return }

        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    if self.requestContextId == requestId {
                        self.recoveryTask = nil
                    }
                    if self.requestContextId == requestId, !self.pendingRecoveryIds.isEmpty {
                        let retryIds = self.pendingRecoveryIds.compactMap { BigUInt($0) }
                        self.pendingRecoveryIds.removeAll()
                        self.scheduleRecovery(for: retryIds)
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
            guard self.isActive(requestId: requestId) else { return }

            let targets = pendingRecoveryIds.compactMap { BigUInt($0) }
            pendingRecoveryIds.removeAll()
            guard !targets.isEmpty else { return }

            var updated = false
            for id in targets {
                guard self.isActive(requestId: requestId) else { return }
                do {
                    let info = try await service.getInfo(id: id)
                    guard self.isActive(requestId: requestId) else { return }
                    let key = id.description
                    cachedInfoById[key] = info

                    if let idx = viewItems.firstIndex(where: { $0.id == key }) {
                        viewItems[idx] = ViewItem(info: info)
                    } else {
                        viewItems.append(ViewItem(info: info))
                    }
                    updated = true
                } catch {
                    guard self.isActive(requestId: requestId) else { return }
                    pendingRecoveryIds.insert(id.description)
                }
            }

            guard self.isActive(requestId: requestId) else { return }
            if updated {
                viewItems.sort { Int($0.info.id) > Int($1.info.id) }
                proposalStorageManager.save(infos: viewItems.map { ProposalInfoRecord(info: $0.info) })
                proposalStorageManager.savePageControl(safe4Page)
                state = .completed(datas: viewItems)
            }
        }
    }
}
// load new Proposal
extension ProposalViewModel {
    func loadNewProposals() {
        self.hasNewProposal = ProposalStorageManager.getNeedShowTips()
        if case .All = service.type {
            Task { @MainActor in
                let totalNum = (try? await service.getTotalNum()) ?? 0
                if let pageControl = proposalStorageManager.getPageControl(), pageControl.totalNum < totalNum {
                    reconcileTotal(latestTotalNum: totalNum)
                    requestInfos(loadMore: false) {
                        self.hasNewProposal = true
                        self.proposalStorageManager.savePageControl(self.safe4Page)
                        ProposalStorageManager.saveNeedShowTips(self.hasNewProposal)
                    }
                }else {
                    requestInfos(loadMore: true) {
                        self.hasNewProposal = self.viewItems.count > 0
                        ProposalStorageManager.saveNeedShowTips(self.hasNewProposal)
                    }
                }
            }
        }
    }
}
// search
extension ProposalViewModel {
    func search(text: String?) {
        searchCautionRelay.accept(nil)
        guard let text, text.count > 0 else {
            state = .completed(datas: viewItems)
            return
        }
        state = .loading
        Task {
            do {
                if let id = BigUInt(text) {
                    let isExist = try await service.exist(id)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.proposal.create.ID.exist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await proposalInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "safe_zone.safe4.proposal.create.ID.input.tips".localized, type: .error)
                    searchCautionRelay.accept(caution)
                    state = .searchResults(datas: [])
                }
            }catch{
                state = .searchResults(datas: [])
            }
        }
    }
    
    private func proposalInfoBy(id: BigUInt) async throws -> ViewItem {
        let info = try await service.getInfo(id: id)
        return ViewItem(info: info)
    }
}

extension ProposalViewModel {
    
    func refresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        requestContextId = nil
        targetTotalNumForCatchUp = nil
        pendingRecoveryIds.removeAll()
        viewItems.removeAll()
        if case .All = service.type {
            if let pageControl = proposalStorageManager.getPageControl(), proposalStorageManager.totalCacheNum > 0 {
                safe4Page.update(totalNum: pageControl.totalNum, page: pageControl.page, indexPath: pageControl.targetIndexPath)
                loadCache()
                if proposalStorageManager.isCacheExpired(maxAge: Self.cacheMaxAge) {
                    requestInfos(loadMore: false, completed: nil)
                }
            } else {
                requestInfos(loadMore: false, completed: nil)
            }
        }else {
            requestInfos(loadMore: false, completed: nil)
        }

    }

    func softRefresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        requestContextId = nil
        targetTotalNumForCatchUp = nil
        pendingRecoveryIds.removeAll()

        guard !viewItems.isEmpty else {
            requestInfos(loadMore: false, completed: nil)
            return
        }

        requestSoftRefresh()
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        guard allRequestTask == nil else { return }
        if safe4Page.isAbleLoadMore {
            requestInfos(loadMore: true, completed: nil)
        }
    }
}

extension ProposalViewModel {
    
    var type: ProposalModule.ProposalType {
        service.type
    }
    
    var stateDriver: Observable<ProposalViewModel.State> {
        stateRelay.asObservable()
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension ProposalViewModel {
    
    enum State {
        case loading
        case completed(datas: [ProposalViewModel.ViewItem])
        case searchResults(datas: [ProposalViewModel.ViewItem])
        case failed(error: String)
    }
        
    struct ViewItem {
        let info: ProposalInfo
        
        var id: String {
            info.id.description
        }
        
        var amount: String {
            info.payAmount.safe4FomattedAmount
        }
        
        var status: ProposalState {
            if Double(info.startPayTime) > Date.now.timeIntervalSince1970 {
                return .voting
            }
            return  info.state == 0 ? .invalid : .passed
        }
        
        var dateText: String {
            let date = Date(timeIntervalSince1970: Double(info.startPayTime))
            return DateHelper().safe4Format(date: date)
        }
        
        var payDateText: String {
            let date = Date(timeIntervalSince1970: Double(info.startPayTime))
            let start = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? Date()// next day
            return DateHelper().safe4Format(date: start)
        }

        var distribution: String {
            if info.payTimes < 2 {
                return "safe_zone.safe4.pay.method.disposabl.desc".localized("\(payDateText)", "\(amount)")
            }
            let date = Date(timeIntervalSince1970: Double(info.endPayTime))
            let end = info.startPayTime == info.startPayTime ? payDateText : DateHelper().safe4Format(date: date)
            return "safe_zone.safe4.pay.method.instalment.desc".localized("\(payDateText)", "\(end)", "\(info.payTimes)", "\(amount)")
        }

    }
    
    enum ProposalState {
        case voting
        case passed
        case invalid
        
        var title: String {
            switch self {
            case .voting:
                return "safe_zone.safe4.state.voting".localized
            case .passed:
                return "safe_zone.safe4.state.passed".localized
            case .invalid:
                return "safe_zone.safe4.state.invalid".localized
            }
        }
        
        var color: UIColor {
            switch self {
            case .voting:
                return .themeIssykBlue
            case .passed:
                return  .themeRemus
            case .invalid:
                return  .themeElena
            }
        }
    }
    
    enum ProposalError: Error {
        case getInfo
    }

}
