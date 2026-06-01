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
    let type: SuperNodeModule.SuperNodeType
    private let service: SuperNodeService
    private let disposeBag = DisposeBag()
    private var safe4Page: Safe4PageControl
    private var partnerSafe4Page: Safe4PageControl
    private var partnerAddressArray = [EthereumAddress]()
    private var nodeStorageManager: NodeStorageManager
    private var cachedInfoByAddress = [String: SuperNodeInfo]()
    private var allRequestTask: Task<Void, Never>?
    private var catchUpTask: Task<Void, Never>?
    private var targetTotalNumForCatchUp: Int?

    private var stateRelay = PublishRelay<SuperNodeViewModel.State>()
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
        self.nodeStorageManager = NodeStorageManager(nodeType: .superNode, pageControl: initialSafe4Page)

        subscribe(disposeBag, service.syncRefreshObservable) { [weak self] _ in self?.refresh() }
    }
}

// Mine
extension SuperNodeViewModel {
    
    private func requestMineNodeInfos(loadMore: Bool) {
        state = .loading
        Task { [service] in
            do {
                var partnerAddrs = [Web3Core.EthereumAddress]()
                if !loadMore {
                   let totalNum = try await service.getAddrNum4Creator()
                    safe4Page.set(totalNum: Int(totalNum))
                    partnerAddrs = try await allPartnerAddrs()
                }
                guard safe4Page.totalNum > 0 || partnerAddressArray.count > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard viewItems.count < safe4Page.totalNum + partnerAddressArray.count else {
                    state = .completed(datas: viewItems)
                    return
                }
                var creatorAddrs = [Web3Core.EthereumAddress]()
                if safe4Page.totalNum > 0 {
                    creatorAddrs = try await service.getAddrs4Creator(page: safe4Page)
                }
                if creatorAddrs.count > 0 { safe4Page.plusPage() }
                let addrs = partnerAddrs + creatorAddrs
                let sortedResults = await fetchNodeItems(addresses: addrs, isEnabledEdit: true)
                viewItems.append(contentsOf: sortedResults)
                state = .completed(datas: viewItems)
            }catch{
                state = .failed(error: "")
            }
        }
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
                        return .failure(SuperNodeError.getInfo)
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
extension SuperNodeViewModel {
    private func requestInfos(loadMore: Bool, showLoading: Bool = true, resetBeforeLoad: Bool = false, refreshHeadIfNeeded: Bool = false) {
        guard allRequestTask == nil else { return }
        if showLoading { state = .loading }

        if resetBeforeLoad {
            safe4Page = Safe4PageControl(pageSize: Self.pageSize)
            viewItems.removeAll()
            cachedInfoByAddress.removeAll()
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
        }

        allRequestTask = Task { [service] in
            defer {
                Task { @MainActor in
                    self.allRequestTask = nil
                    self.startBackgroundCatchUpIfNeeded()
                }
            }
            do{
                if !loadMore { let _ = try await allPartnerAddrs() }
                let latestTotalNum = try await Int(service.getTotalNum())
                reconcileTotal(latestTotalNum: latestTotalNum)

                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }

                if refreshHeadIfNeeded, !loadMore {
                    try await refreshHeadPage()
                }

                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }
                let addrs = try await service.superNodeAddressArray(page: safe4Page)
                if addrs.count > 0 { safe4Page.plusPage() }
                let sortedResults = await fetchNodeItems(addresses: addrs, isEnabledEdit: false)
                nodeStorageManager.save(pageControl: safe4Page, infos: sortedResults.map { Safe4NodeInfo(recordId: NodeStorageType.superNode.cacheId, $0.info) })
                viewItems.append(contentsOf: sortedResults)
                cacheItems = viewItems
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
    
    private func nodeInfoBy(address: Web3Core.EthereumAddress, isEnabledEdit: Bool) async throws -> ViewItem {
        async let allVoteNum = try service.getAllVoteNum()
        async let totalVoteNum = try service.getTotalVoteNum(address: address)
        async let totalAmount = try service.getTotalAmount(address: address)
        let info: SuperNodeInfo
        if let cached = cachedInfoByAddress[address.address.lowercased()] {
            info = cached
        } else {
            info = try await service.getInfo(address: address)
            cachedInfoByAddress[address.address.lowercased()] = info
        }

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
        return try await ViewItem(info: info, totalVoteNum: totalVoteNum, totalAmount: totalAmount, allVoteNum: allVoteNum, ownerType: ownerType, nodeType: nodeType, isEnabledEdit: isEnabledEdit)
    }
}

extension SuperNodeViewModel {
    func refresh() {
        allRequestTask?.cancel()
        allRequestTask = nil
        catchUpTask?.cancel()
        catchUpTask = nil
        targetTotalNumForCatchUp = nil
        viewItems.removeAll()
        switch type {
        case .All:
            let hasCache = loadCache()
            if hasCache {
                // cache does not include live vote metrics, so always re-sync in background
                requestInfos(loadMore: false, showLoading: false, resetBeforeLoad: false, refreshHeadIfNeeded: true)
            } else {
                requestInfos(loadMore: false, showLoading: true, resetBeforeLoad: true)
            }
        case .Mine:
            requestMineNodeInfos(loadMore: false)
        }
    }
    
    func clearCaches() {
        if case .All = type {
            allRequestTask?.cancel()
            allRequestTask = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            targetTotalNumForCatchUp = nil
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
            if safe4Page.isAbleLoadMore {
                requestInfos(loadMore: true)
            }
        case .Mine:
            requestMineNodeInfos(loadMore: true)
        }
    }
    
    func getLockId(viewItem: ViewItem) -> BigUInt? {
        return viewItem.info.founders
            .filter{$0.addr.address.lowercased() == service.address.address.lowercased()}.first?.lockID
    }

    @discardableResult
    private func loadCache() -> Bool {
        guard let pageControl = nodeStorageManager.getPageControl(), let caches = nodeStorageManager.load(), !caches.isEmpty else {
            return false
        }

        let cacheItems = caches.map {
            ViewItem(
                info: $0.transformToSuper(),
                totalVoteNum: 0,
                totalAmount: 0,
                allVoteNum: 0,
                ownerType: ownerType(info: $0.transformToSuper()),
                nodeType: nodeType,
                isEnabledEdit: false
            )
        }

        self.cacheItems = cacheItems
        self.viewItems = cacheItems
        cachedInfoByAddress = Dictionary(uniqueKeysWithValues: cacheItems.map { ($0.info.addr.address.lowercased(), $0.info) })
        safe4Page.update(totalNum: pageControl.totalNum, page: pageControl.page, indexPath: pageControl.targetIndexPath)
        state = .completed(datas: viewItems)
        return true
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
            targetTotalNumForCatchUp = nil
            return
        }
        if latestTotalNum == currentTotal {
            return
        }
        if latestTotalNum < currentTotal {
            viewItems.removeAll()
            cacheItems.removeAll()
            cachedInfoByAddress.removeAll()
            nodeStorageManager.clearCaches()
            safe4Page = Safe4PageControl(pageSize: Self.pageSize)
            safe4Page.set(totalNum: latestTotalNum)
            targetTotalNumForCatchUp = nil
            catchUpTask?.cancel()
            catchUpTask = nil
            return
        }
        safe4Page = buildPageControl(totalNum: latestTotalNum, loadedCount: loadedCount)
        targetTotalNumForCatchUp = latestTotalNum
    }

    private func fetchNodeItems(addresses: [Web3Core.EthereumAddress], isEnabledEdit: Bool) async -> [ViewItem] {
        var results = [ViewItem]()
        for address in addresses {
            if Task.isCancelled { break }
            if let item = try? await nodeInfoBy(address: address, isEnabledEdit: isEnabledEdit) {
                results.append(item)
            }
        }
        return results
    }

    private func buildPageControl(totalNum: Int, loadedCount: Int) -> Safe4PageControl {
        var control = Safe4PageControl(pageSize: Self.pageSize)
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
        guard case .All = type else { return }
        guard catchUpTask == nil else { return }
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
                    self.catchUpTask = nil
                    self.startBackgroundCatchUpIfNeeded()
                }
            }

            while !Task.isCancelled {
                guard let targetTotal = targetTotalNumForCatchUp else { break }
                if viewItems.count >= targetTotal {
                    targetTotalNumForCatchUp = nil
                    break
                }
                if allRequestTask != nil {
                    break
                }
                guard safe4Page.isAbleLoadMore else { break }

                do {
                    let addrs = try await service.superNodeAddressArray(page: safe4Page)
                    guard !addrs.isEmpty else { break }
                    safe4Page.plusPage()

                    let items = await fetchNodeItems(addresses: addrs, isEnabledEdit: false)
                    mergeInOrder(items: items)
                    nodeStorageManager.save(pageControl: safe4Page, infos: items.map { Safe4NodeInfo(recordId: NodeStorageType.superNode.cacheId, $0.info) })
                    state = .completed(datas: viewItems)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func refreshHeadPage() async throws {
        var headPage = Safe4PageControl(pageSize: Self.pageSize)
        headPage.set(totalNum: safe4Page.totalNum)
        let addresses = try await service.superNodeAddressArray(page: headPage)
        guard !addresses.isEmpty else { return }

        let headItems = await fetchNodeItems(addresses: addresses, isEnabledEdit: false)
        guard !headItems.isEmpty else { return }

        var indexById = Dictionary(uniqueKeysWithValues: viewItems.enumerated().map { ($1.id, $0) })

        for item in headItems {
            cachedInfoByAddress[item.info.addr.address.lowercased()] = item.info
            if let idx = indexById[item.id] {
                viewItems[idx] = item
            } else {
                viewItems.insert(item, at: 0)
                indexById = Dictionary(uniqueKeysWithValues: viewItems.enumerated().map { ($1.id, $0) })
            }
        }

        // Keep server page order for the refreshed head window.
        var replacement = [ViewItem]()
        for item in headItems {
            if let idx = viewItems.firstIndex(where: { $0.id == item.id }) {
                replacement.append(viewItems[idx])
            }
        }

        if !replacement.isEmpty {
            let count = min(replacement.count, viewItems.count)
            viewItems.replaceSubrange(0..<count, with: replacement)
        }

        cacheItems = viewItems
        nodeStorageManager.save(pageControl: safe4Page, infos: headItems.map { Safe4NodeInfo(recordId: NodeStorageType.superNode.cacheId, $0.info) })
        state = .completed(datas: viewItems)
    }

    private func mergeInOrder(items: [ViewItem]) {
        guard !items.isEmpty else { return }
        var existingIds = Set(viewItems.map(\.id))
        for item in items {
            guard !existingIds.contains(item.id) else { continue }
            existingIds.insert(item.id)
            viewItems.append(item)
            cachedInfoByAddress[item.info.addr.address.lowercased()] = item.info
        }
        cacheItems = viewItems
    }
}

extension SuperNodeViewModel {
    
    var stateDriver: Observable<SuperNodeViewModel.State> {
        stateRelay.asObservable()
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
            guard let allVoteNum = Decimal(bigUInt: allVoteNum, decimals: safe4Decimals) else { return 0 }
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
