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
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let service: LockedRecordService
    private let lockedRecoardStorage: Safe4LockedRecordStorage
    private var votedPageControl = Safe4PageControl(pageSize: 20)
    private var lockedPageControl = Safe4PageControl(pageSize: 20)
    private var lockedPageControl_01 = Safe4PageControl(pageSize: 20)
    private var lockedPageControl_02 = Safe4PageControl(pageSize: 20)
    private var proposalPageControl = Safe4PageControl(pageSize: 20)
    private var listTask: Task<Void, Never>?
    private var withdrawTask: Task<Void, Never>?
    private var cacheItems: [WithdrawItemRecord] = []
    
    @Published private(set) var dataState: ListState = .items
    @Published private(set) var sendState: WithdrawStatus = .normal
    @Published private(set) var hasMoreItems = true
    @Published private(set) var viewItems: [WithdrawItemRecord] = []

    init(service: LockedRecordService, lockedStorage: Safe4LockedRecordStorage) {
        self.service = service
        self.lockedRecoardStorage = lockedStorage
        showCache()
        let shouldSync = viewItems.isEmpty || isCacheExpired(maxAge: Self.cacheMaxAge)
        if shouldSync {
            requestItems(loadMore: false)
        } else {
            dataState = .items
            hasMoreItems = true
        }
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

    private func withdraw(items: [WithdrawItemRecord]) {
        guard withdrawTask == nil else { return }
        guard !items.isEmpty else { return }
        sendState = .loading
        let snapshotItems = items
        withdrawTask = Task {
            defer {
                Task { @MainActor in
                    self.withdrawTask = nil
                }
            }
            do{
                let smallAmount_01 = snapshotItems.filter { $0.sourceType == .smallAmount01 }.map { BigUInt($0.id) }
                let smallAmount_02 = snapshotItems.filter { $0.sourceType == .smallAmount02 }.map { BigUInt($0.id) }
                let native = snapshotItems.filter {
                    switch $0.sourceType {
                    case .smallAmount01, .smallAmount02:
                        return false
                    default:
                        return true
                    }
                }.map { BigUInt($0.id) }
                
                for chunk in smallAmount_01.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .smallAmount_01, ids: chunk)
                }
                for chunk in smallAmount_02.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .smallAmount_02, ids: chunk)
                }
                
                for chunk in native.chunked(into: Self.withdrawBatchSize) where !chunk.isEmpty {
                    _ = try await service.withdrawByID(type: .native, ids: chunk)
                }
                
                await MainActor.run {
                    let withdrawnKeys = Set(snapshotItems.map(\.cacheKey))
                    viewItems.removeAll { withdrawnKeys.contains($0.cacheKey) }
                    snapshotItems.forEach { item in
                        lockedRecoardStorage.delete(type: item.sourceType, by: item.id)
                    }
                    cacheItems = viewItems
                    hasMoreItems = canLoadMore
                    persistCacheTimestamp()
                    LockedRecordViewModel.saveDidWithdrawIds(snapshotItems.map { $0.id.description })
                    sendState = .success(message: "safe_zone.safe4.withdraw".localized + "transactions.types.outgoing".localized)
                }
            }catch{
                await MainActor.run {
                    sendState = .failed(error: "settings.personal_support.failed".localized)
                }
            }
        }
    }

    func loadMore() {
        if case .loading = dataState {
            return
        }
        requestItems(loadMore: true)
    }
    
    var withdrawEnableIds: [BigUInt] {
        viewItems.filter{$0.withdrawEnable}.map{BigUInt($0.id)}
    }

    var hasWithdrawableItems: Bool {
        viewItems.contains { $0.withdrawEnable }
    }
    
    func allWithdraw() {
        let items = viewItems.filter { $0.withdrawEnable }
        guard !items.isEmpty else{ return }
        guard case .items = dataState else{ return }
        withdraw(items: items)
    }
}

extension LockedRecordViewModel {
    func requestItems(loadMore: Bool) {
        guard listTask == nil else { return }
        dataState = .loading
        listTask = Task {
            defer {
                Task { @MainActor in
                    self.listTask = nil
                }
            }
            do{
                if !loadMore {
                    async let lockedTotalNum = service.totalLockedNum(type: .native)
                    async let lockedTotalNum_01 = service.totalLockedNum(type: .smallAmount_01)
                    async let lockedTotalNum_02 = service.totalLockedNum(type: .smallAmount_02)
                    async let votedTotalNum = service.getVotedIDNum4Voter()
                    async let proposalTotalNum = service.mineProposalNum()
                    
                    let nativeTotal = try await Int(lockedTotalNum)
                    let smallAmount01Total = try await Int(lockedTotalNum_01)
                    let smallAmount02Total = try await Int(lockedTotalNum_02)
                    let votedTotal = try await Int(votedTotalNum)
                    let proposalTotal = try await Int(proposalTotalNum)
                    
                    lockedPageControl.set(totalNum: nativeTotal)
                    lockedPageControl_01.set(totalNum: smallAmount01Total)
                    lockedPageControl_02.set(totalNum: smallAmount02Total)
                    votedPageControl.set(totalNum: votedTotal)
                    proposalPageControl.set(totalNum: proposalTotal)
                }
                
                guard lockedPageControl.isAbleLoadMore || lockedPageControl_01.isAbleLoadMore || lockedPageControl_02.isAbleLoadMore || votedPageControl.isAbleLoadMore || proposalPageControl.isAbleLoadMore else {
                    await MainActor.run {
                        hasMoreItems = false
                        dataState = .items
                    }
                    return
                }
                var tempItems = [WithdrawItemRecord]()
                
                async let items_0 = Locked_native()
                async let items_1 = Locked_01()
                async let items_2 = Locked_02()
                async let items_3 = voted()
                async let items_4 = proposal()
                
                tempItems = try await (items_0 + items_1 + items_2 + items_3 + items_4)
                tempItems.append(contentsOf: viewItems)
                let uniqueItems = dedupById(items: tempItems)
                
                await MainActor.run {
                    viewItems = uniqueItems
                    sortItems()
                    cacheItems = viewItems
                    hasMoreItems = canLoadMore
                    if !loadMore {
                        try? lockedRecoardStorage.clear()
                        let records = viewItems.map { $0.asLockedRecord() }
                        lockedRecoardStorage.save(recoards: records)
                    }
                    persistCacheTimestamp()
                    dataState = .items
                }
            }catch{
                await MainActor.run {
                    if viewItems.isEmpty {
                        dataState = .error(RequestError.getInfo as NSError)
                    } else {
                        dataState = .items
                    }
                }
            }
        }
    }
    private func sortItems() {
        viewItems.sort {
            switch ($0.withdrawEnable, $1.withdrawEnable) {
               case (false, false): return Int($0.id) < Int($1.id)
               case (false, true): return false
               case (true, false): return true
               case (true, true): return Int($0.id) < Int($1.id)
            }
        }
    }

    private var canLoadMore: Bool {
        lockedPageControl.isAbleLoadMore ||
        lockedPageControl_01.isAbleLoadMore ||
        lockedPageControl_02.isAbleLoadMore ||
        votedPageControl.isAbleLoadMore ||
        proposalPageControl.isAbleLoadMore
    }

    private func dedupById(items: [WithdrawItemRecord]) -> [WithdrawItemRecord] {
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
    
    private func Locked_native() async throws -> [WithdrawItemRecord] {
        if lockedPageControl.isAbleLoadMore {
            let lockedIds = try await service.getLockedIDs(type: .native, start: BigUInt(lockedPageControl.start), count: BigUInt(lockedPageControl.currentPageCount))
            let results = try await getRecordInfos(type: .native, ids: lockedIds)
            let items = buildViewItems(results: results, sourceType: .locked)
            if results.count > 0 {
                lockedPageControl.plusPage()
            }
            return items
        }
        return []
    }
    
    private func Locked_01() async throws -> [WithdrawItemRecord] {
        if lockedPageControl_01.isAbleLoadMore {
            let lockedIds = try await service.getLockedIDs(type: .smallAmount_01, start: BigUInt(lockedPageControl_01.start), count: BigUInt(lockedPageControl_01.currentPageCount))
            let results = try await getRecordInfos(type: .smallAmount_01, ids: lockedIds)
            let items = buildViewItems(results: results, sourceType: .smallAmount01)
            if results.count > 0 {
                lockedPageControl_01.plusPage()
            }
            return items
        }
        return []
    }
    
    private func Locked_02() async throws -> [WithdrawItemRecord] {
        if lockedPageControl_02.isAbleLoadMore {
            let lockedIds = try await service.getLockedIDs(type: .smallAmount_02, start: BigUInt(lockedPageControl_02.start), count: BigUInt(lockedPageControl_02.currentPageCount))
            let results = try await getRecordInfos(type: .smallAmount_02, ids: lockedIds)
            let items = buildViewItems(results: results, sourceType: .smallAmount02)
            if results.count > 0 {
                lockedPageControl_02.plusPage()
            }
            return items
        }
        return []
    }
    
    private func voted() async throws -> [WithdrawItemRecord] {
        if votedPageControl.isAbleLoadMore {
            let votedIds = try await service.getVotedIDs4Voter(start: BigUInt(votedPageControl.start), count: BigUInt(votedPageControl.currentPageCount))
            let results = try await getRecordInfos(type: .native, ids: votedIds)
            let items = buildViewItems(results: results, sourceType: .voted)
            if results.count > 0 {
                votedPageControl.plusPage()
            }
            return items
        }
        return []
    }
    
    private func proposal() async throws -> [WithdrawItemRecord] {
        if proposalPageControl.isAbleLoadMore {
            let proposalIds = try await service.mineProposalIds(start: BigUInt(proposalPageControl.start), count: BigUInt(proposalPageControl.currentPageCount))
            let lockIds = try await mineProposalLockIds(ids: proposalIds)
            let results = try await getRecordInfos(type: .native, ids: lockIds)
            let items = buildViewItems(results: results.filter{$0.1?.frozenAddr.address != nullAddress}, sourceType: .proposal)
            if results.count > 0 {
                proposalPageControl.plusPage()
            }
            return items
        }
        return []
    }
    
    private func buildViewItems(results: [(web3swift.AccountRecord, RecordUseInfo?)], sourceType: LockedRecordSourceType) -> [WithdrawItemRecord] {
        let datas = results.filter{$0.0.id != 0}.map { (recordItem, userInfo) in
            let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
            let record = Safe4AccountRecord(record: recordItem)
            var info: Safe4RecordUseInfo? = nil
            if userInfo != nil {
                info = Safe4RecordUseInfo(info: userInfo!)
            }
            return WithdrawItemRecord(lastBlockHeight: lastBlockHeight,
                                      sourceType: sourceType,
                                      record: record,
                                      info: info
            )
        }
        return datas
    }
    
    private func getRecordInfos(type: web3swift.AccountManager.ContractType, ids: [BigUInt]) async throws -> [(web3swift.AccountRecord, RecordUseInfo?)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo?)] = []
        for id in ids {
            do {
                let info = try await service.getRecordByID(type: type, id: id)
                var useInfo: RecordUseInfo? = nil
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
    
    private func mineProposalLockIds(ids: [BigUInt]) async throws -> [BigUInt] {
        var lockIds = [BigUInt]()
        for id in ids {
            let rewardIDs =  try await service.getProposalRewardIDs(id: id)
            lockIds.append(contentsOf: rewardIDs)
        }
        return lockIds
    }

    private var cacheTimestampKey: String {
        "\(LockedRecordCacheTimestampKey)_\(service.userAddress.address.lowercased())"
    }

    private func showCache() {
        do {
            let items = try lockedRecoardStorage.allRecords().map { item in
                let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
                return WithdrawItemRecord(lastBlockHeight: lastBlockHeight, sourceType: item.sourceType, record: item.record, info: item.info)
            }
            viewItems = items
            sortItems()
            cacheItems = viewItems
        } catch {}
    }

    private func persistCacheTimestamp(_ timestamp: TimeInterval = Date().timeIntervalSince1970) {
        userDefaultsStorage.set(value: timestamp, for: cacheTimestampKey)
    }

    private func isCacheExpired(maxAge: TimeInterval) -> Bool {
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
            case (.success(let lhsMsg), .success(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.failed(let lhsError), .failed(let rhsError)):
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
        guard let ids: [String] = Core.shared.userDefaultsStorage.value(for: LockedRecordWithdrawIdsKey) else{ return [] }
        return ids
    }
    
    static func saveDidWithdrawIds(_ ids: [String]) {
        var oldIds = LockedRecordViewModel.getDidWithdrawIds()
        oldIds.append(contentsOf: ids)
        oldIds = Array(Set(oldIds))
        Core.shared.userDefaultsStorage.set(value: oldIds, for: LockedRecordWithdrawIdsKey)
    }
}
private let LockedRecordWithdrawIdsKey: String = "safe4_LockedRecord_WithdrawIds_key"
private let LockedRecordCacheTimestampKey: String = "safe4_locked_record_cache_timestamp_key"


extension Sequence {
    func sorted(by first: (Element, Element) -> Bool, _ others: ((Element, Element) -> Bool)...) -> [Element] {
        return sorted { a, b in
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
    
    init(lastBlockHeight: BigUInt, sourceType: LockedRecordSourceType, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        let releaseHeight = BigUInt(info?.releaseHeight ?? "0") ?? BigUInt.zero
        let unlockHeight = BigUInt(record.unlockHeight) ?? BigUInt.zero
        let votedddress = info?.votedAddr ?? nullAddress
        let withdrawEnable = (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) || (unlockHeight.isZero && (releaseHeight < lastBlockHeight))
        let addLockDayEnable = (record.type != 0 || votedddress == nullAddress) ? false : unlockHeight > 0
        let amount = (BigUInt(record.amount) ?? BigUInt.zero).safe4FomattedAmount + " SAFE"
        
        let didWithdrawIds = LockedRecordViewModel.getDidWithdrawIds()
        let isWithdraw = didWithdrawIds.contains(record.id.description)
        self.id = record.id
        self.sourceType = sourceType
        self.amount = amount
        self.unlockHeight = Int(unlockHeight)
        self.releaseHeight = releaseHeight.isZero ? nil : Int(releaseHeight)
        self.address = votedddress == nullAddress ? nil : votedddress
        self.withdrawEnable = withdrawEnable && !isWithdraw
        self.addLockDayEnable = addLockDayEnable
        self.record = record
        self.info = info
    }
    
    init(id: Int, sourceType: LockedRecordSourceType, amount: String, unlockHeight: Int, releaseHeight: Int?, address: String?, withdrawEnable: Bool, addLockDayEnable: Bool, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
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
        lhs.sourceType == rhs.sourceType &&
        lhs.amount == rhs.amount &&
        lhs.unlockHeight == rhs.unlockHeight &&
        lhs.releaseHeight == rhs.releaseHeight &&
        lhs.address == rhs.address
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(sourceType.rawValue)
        hasher.combine(amount)
        hasher.combine(unlockHeight)
        hasher.combine(releaseHeight)
        hasher.combine(address)
    }

    func asLockedRecord() -> Safe4LockedRecord {
        Safe4LockedRecord(type: sourceType, record: record, info: info)
    }
}
