import Combine
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

private let WithdrawIdsKey: String = "safe4_WithdrawIds_key"
private let RemoveVoteIdsKey: String = "safe4_RemoveVoteIds_key"
private let WithdrawCacheTimestampKey: String = "safe4_withdraw_cache_timestamp_key"

class WithdrawViewModel: ObservableObject {
    private static let pageSize = 20
    private static let cacheMaxAge: TimeInterval = 120
    private static let withdrawBatchSize = 30
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let service: WithdrawViewService
    private let withdrawLockedStorage: Safe4WithdrawLockedStorage
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    
    @Published private(set) var sendState: SendStatus = .normal
    @Published private(set) var dataState: ListState = .items
    @Published private(set) var hasMoreItems = true
    @Published private(set) var viewItems: [WithdrawItem] = []
    
    private var pageControl = Safe4PageControl(pageSize: 20)
    private var withdrawTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    private var cacheItems = [WithdrawItem]()
    @Published var selectedItems: [WithdrawItem] = [] {
        didSet {
            withdrawEnabled = selectedItems.count > 0
        }
    }
    @Published var withdrawEnabled = false
    @Published var isLoadAll = false
    
    var onSuccess: ((SendStatus) -> Void)?
        
    init(service: WithdrawViewService, withdrawLockedStorage: Safe4WithdrawLockedStorage) {
        self.service = service
        self.withdrawLockedStorage = withdrawLockedStorage
        
        showCache()
        let shouldSync = viewItems.isEmpty || isCacheExpired(maxAge: Self.cacheMaxAge)
        if shouldSync {
            withdrawItems(loadMore: false)
        } else {
            dataState = .items
            hasMoreItems = true
        }
    }
}

extension WithdrawViewModel {
    func choose(item: WithdrawItem) {
        if let index = selectedItems.firstIndex(where: { $0.id == item.id }) {
            selectedItems.remove(at: index)
        }else {
            selectedItems.append(item)
        }
    }
    
    func isSelected(item: WithdrawItem) -> Bool {
        if let _ = selectedItems.firstIndex(where: { $0.id == item.id }) {
            return true
        }else {
            return false
        }
    }
    
    func withdraw() {
        guard withdrawTask == nil else { return }
        guard !selectedItems.isEmpty else { return }

        sendState = .loading
        withdrawEnabled = false
        let snapshot = selectedItems
       
        withdrawTask = Task {
            defer {
                Task { @MainActor in
                    self.withdrawTask = nil
                }
            }
            do{
                if service.type == .voteLocked {
                    let recordIDs = snapshot.filter{$0.isRemoveVoteEnable}.map { $0.id }
                    if recordIDs.count > 0 {
                        for chunk in recordIDs.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                            _ = try await service.removeVoteOrApproval(recordIDs: chunk)
                        }
                        WithdrawViewModel.saveRemoveVoteIds(recordIDs.map{$0.description})
                    }
                    let ids = snapshot.filter{$0.isWithdrawEnable}.map { $0.id }
                    if  ids.count > 0 {
                        for chunk in ids.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                            _ = try await service.withdrawByID(type: .native, ids: chunk)
                        }
                        WithdrawViewModel.saveDidWithdrawIds(ids.map{$0.description})
                    }
                }else {
                    let ids = snapshot.map { $0.id }
                    for chunk in ids.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                        _ = try await service.withdrawByID(type: .native, ids: chunk)
                    }
                    WithdrawViewModel.saveDidWithdrawIds(ids.map{$0.description})
                }
                await MainActor.run {
                    removeItems(ids: Set(snapshot.map(\.id)))
                    selectedItems.removeAll()
                    if case .voteLocked = service.type {
                        if !snapshot.filter({ $0.isWithdrawEnable }).isEmpty {
                            let withdrawIds = Set(snapshot.filter { $0.isWithdrawEnable }.map(\.id))
                            cacheItems.removeAll { withdrawIds.contains($0.id) }
                            viewItems = cacheItems
                        } else {
                            viewItems = cacheItems
                        }
                    }
                    sendState = .completed
                    withdrawEnabled = true
                    onSuccess?(sendState)
                }
            }catch{
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
        viewItems.filter{$0.isSelEnable == true}
    }
    
    var isChoosedAll: Bool {
        return (enableItems.count > 0) && selectedItems == enableItems
    }
    
    var title: String {
        service.type.title
    }
    
    var withdrawType: SafeWithdrawType {
        service.type
    }
    
    private func showCache() {
        do {
            switch service.type {
            case .masterNode:
                let records = try withdrawLockedStorage.allRecords(by: .masterNode)
                viewItems = records.map{
                    WithdrawItem(type: service.type,
                                 lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                                 record: $0.record,
                                 info: $0.info
                    )
                }.filter{$0.isSelEnable}
            case .superNode:
                let records = try withdrawLockedStorage.allRecords(by: .superNode)
                viewItems = records.map{
                    WithdrawItem(type: service.type,
                                 lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                                 record: $0.record,
                                 info: $0.info
                    )
                }.filter{$0.isSelEnable}
            case .voteLocked:
                let records = try withdrawLockedStorage.allRecords(by: .voteLocked)
                viewItems = records.map{
                    WithdrawItem(type: service.type,
                                 lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                                 record: $0.record,
                                 info: $0.info
                    )
                }.filter{$0.isSelEnable}
            case .proposal:
                let records = try withdrawLockedStorage.allRecords(by: .proposal)
                viewItems = records.map{
                    WithdrawItem(type: service.type,
                                 lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                                 record: $0.record,
                                 info: $0.info
                    )
                }.filter{$0.isSelEnable}
                
            }
            
            viewItems.sort(by:{ Int($0.id) < Int($1.id) })
            cacheItems = viewItems
        }catch{}

    }
}

extension WithdrawViewModel {
    
    func loadMore() {
        if case .loading = dataState { return }
        guard listTask == nil else { return }
        withdrawItems(loadMore: true)
    }
    
    func withdrawItems(loadMore: Bool) {
        guard listTask == nil else { return }
        dataState = .loading

        if !loadMore {
            switch service.type {
            case .masterNode:
                try? withdrawLockedStorage.clear(type: .masterNode)
            case .superNode:
                try? withdrawLockedStorage.clear(type: .superNode)
            case .voteLocked:
                try? withdrawLockedStorage.clear(type: .voteLocked)
            case .proposal:
                try? withdrawLockedStorage.clear(type: .proposal)
            }
            cacheItems.removeAll()
        }

        listTask = Task {
            defer {
                Task { @MainActor in
                    self.listTask = nil
                }
            }
            do{
                let ids = try await ids(type: .native, isLoadMore: loadMore)
                guard ids.count > 0 else{
                    await MainActor.run {
                        hasMoreItems = false
                         dataState = .items
                    }
                    return
                }
                let infos = try await getRecordInfos(ids: ids)
                
                var results: [Safe4WithdrawLockedRecord] = []
                switch service.type {
                case .masterNode:
                    let tempArray = infos.filter{$0.1.frozenAddr.address != nullAddress}
                    let array = await node(nodeType: .masterNode, records: tempArray)
                    let recoards = array.map{Safe4WithdrawLockedRecord(type: .masterNode, record: Safe4AccountRecord(record: $0.0), info: Safe4RecordUseInfo(info: $0.1))}
                    withdrawLockedStorage.save(type: .masterNode, recoards: recoards)
                    results = recoards
                    
                case .superNode:
                    let tempArray = infos.filter{$0.1.frozenAddr.address != nullAddress}
                    let array = await node(nodeType: .superNode, records: tempArray)
                    let recoards = array.map{Safe4WithdrawLockedRecord(type: .superNode, record: Safe4AccountRecord(record: $0.0), info: Safe4RecordUseInfo(info: $0.1))}
                    withdrawLockedStorage.save(type: .superNode, recoards: recoards)
                    results = recoards
                                        
                case .voteLocked:
                    let voteArray = infos.filter{$0.1.votedAddr.address != nullAddress}
                    let recoards = voteArray.map{Safe4WithdrawLockedRecord(type: .voteLocked, record: Safe4AccountRecord(record: $0.0), info: Safe4RecordUseInfo(info: $0.1))}
                    withdrawLockedStorage.save(type: .voteLocked, recoards: recoards)
                    results = recoards
                    
                case .proposal:
                    let tempArray = infos.filter{$0.1.frozenAddr.address != nullAddress}
                    let recoards = tempArray.map{Safe4WithdrawLockedRecord(type: .proposal, record: Safe4AccountRecord(record: $0.0), info: Safe4RecordUseInfo(info: $0.1))}
                    withdrawLockedStorage.save(type: .proposal, recoards: recoards)
                    results = recoards
                }
                
                if infos.count > 0 {
                    pageControl.plusPage()
                }
                
                var datas = results.map{
                    WithdrawItem(type: service.type,
                                 lastBlockHeight: BigUInt(service.lastBlockHeight ?? 0),
                                 record: $0.record,
                                 info: $0.info
                    )
                }
                datas.append(contentsOf: viewItems)
                let uniqueItems = datas.filter{$0.isSelEnable}.reduce(into: [WithdrawItem]()) { result, item in
                     if !result.contains(where: { $0.id == item.id }) {
                         result.append(item)
                     }
                 }
                
                await MainActor.run {
                    viewItems = uniqueItems
                    cacheItems = uniqueItems
                    viewItems.sort(by:{ Int($0.id) < Int($1.id) })
                    dataState = .items
                    hasMoreItems = infos.count > 0
                    saveCacheTimestamp()
                }
            }catch{
                await MainActor.run {
                    if viewItems.isEmpty {
                        dataState = .error(RequestError.getInfo as NSError)
                    }
                }
            }
        }
    }
    
    private func ids(type: web3swift.AccountManager.ContractType, isLoadMore: Bool) async throws -> [BigUInt] {
        if !isLoadMore {
            pageControl = Safe4PageControl(pageSize: Self.pageSize)
            try await pageControl(type: type)
        }
        guard pageControl.isAbleLoadMore else {
            return []
        }
        let ids = try await ids(type: type, start: pageControl.start, count: pageControl.currentPageCount).filter{$0 != 0}
        return ids
    }
    
    private func getRecordInfos(ids: [BigUInt]) async throws -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo)] = []
        for id in ids {
            if Task.isCancelled { break }
            do {
                let useInfo = try await service.getRecordUseInfo(id: id)
                let info = try await service.getRecordByID(id: id)
                results.append((info, useInfo))
            } catch {
            }
        }
        return results
    }
        
    private func pageControl(type: web3swift.AccountManager.ContractType) async throws {
        let totalNum: BigUInt
        
        switch service.type {
        case .masterNode, .superNode:
            totalNum = try await service.totalNum(type: type)
        case .proposal:
            totalNum = try await service.mineProposalNum()
        case .voteLocked:
            totalNum = try await service.getVotedIDNum4Voter()
        }
        pageControl.set(totalNum: Int(totalNum))
    }
    
    private func mineProposalLockIds(ids: [BigUInt]) async throws -> [BigUInt] {
        var lockIds = [BigUInt]()
        for id in ids {
            let rewardIDs =  try await service.getProposalRewardIDs(id: id)
            lockIds.append(contentsOf: rewardIDs)
        }
        return lockIds
    }
    
    private func ids(type: web3swift.AccountManager.ContractType, start: Int, count: Int) async throws -> [BigUInt] {
        var ids: [BigUInt] = []
        switch service.type {
        case .masterNode, .superNode:
            ids = try await service.getAvailableIDs(type: type, start: BigUInt(start), count: BigUInt(count))
            
        case .proposal:
            let proposalIds = try await service.mineProposalIds(start: BigUInt(start), count: BigUInt(count))
            ids = try await mineProposalLockIds(ids: proposalIds)
            
        case .voteLocked:
            ids = try await service.getVotedIDs4Voter(start: BigUInt(start), count: BigUInt(count))
        }
        return ids
    }
    
    private func node(nodeType: WithdrawViewService.NodeType, records: [(web3swift.AccountRecord, RecordUseInfo)]) async -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo)] = []
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
            } catch {
            }
        }
        return results
    }
    static func getDidWithdrawIds() -> [String] {
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: WithdrawIdsKey) else{ return [] }
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
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: RemoveVoteIdsKey) else{ return [] }
        return ids
    }

    private func removeItems(ids: Set<BigUInt>) {
        guard !ids.isEmpty else { return }
        viewItems.removeAll { ids.contains($0.id) }
        cacheItems = viewItems
    }

    private func saveCacheTimestamp() {
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheTimestampKey)
    }

    private func isCacheExpired(maxAge: TimeInterval) -> Bool {
        guard let timestamp: TimeInterval = userDefaultsStorage.value(for: cacheTimestampKey) else {
            return true
        }
        return Date().timeIntervalSince1970 - timestamp > maxAge
    }

    private var cacheTimestampKey: String {
        "\(WithdrawCacheTimestampKey)_\(service.type.rawValue)"
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
}

struct WithdrawItem: Equatable, Hashable, Identifiable {
    let id: BigUInt
    let amount: String
    let unlockHeight: BigUInt
    let releaseHeight: BigUInt
    let address: String
    
    let isWithdrawEnable: Bool
    let isRemoveVoteEnable: Bool
    
    var idStr: String {
        id.description
    }
    
    var isSelEnable: Bool {
        isWithdrawEnable || isRemoveVoteEnable
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    init(type: SafeWithdrawType, lastBlockHeight: BigUInt, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        let releaseHeight = BigUInt(info?.releaseHeight ?? "0") ?? BigUInt.zero
        let unlockHeight = BigUInt(record.unlockHeight) ?? BigUInt.zero
        let address = info?.votedAddr ?? ""
        let withdrawEnable = (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) || (unlockHeight.isZero && (releaseHeight < lastBlockHeight))
        let isRemoveVoteEnable = type == .voteLocked ? (releaseHeight.isZero ? false : releaseHeight < lastBlockHeight) : false
        let amount = (BigUInt(record.amount) ?? BigUInt.zero).safe4FomattedAmount + " SAFE"
        
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
        self.isRemoveVoteEnable = isRemoveVoteEnable && !isRemoveVote
    }
    
    init(id: BigUInt, amount: String, unlockHeight: BigUInt, releaseHeight: BigUInt, address: String, isWithdrawEnable: Bool, isRemoveVoteEnable: Bool) {
        self.id = id
        self.amount = amount
        self.unlockHeight = unlockHeight
        self.releaseHeight = releaseHeight
        self.address = address
        self.isWithdrawEnable = isWithdrawEnable
        self.isRemoveVoteEnable = isRemoveVoteEnable
    }
}
