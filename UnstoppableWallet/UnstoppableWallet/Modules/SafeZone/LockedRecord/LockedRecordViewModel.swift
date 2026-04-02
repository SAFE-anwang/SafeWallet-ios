import Combine
import UIKit
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

class LockedRecordViewModel: ObservableObject {
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let service: LockedRecordService
    private let lockedRecoardStorage: Safe4LockedRecordStorage
    private var votedPageControl = Safe4PageControl(pageSize: 20)
    private var lockedPageControl = Safe4PageControl(pageSize: 20)
    private var lockedPageControl_01 = Safe4PageControl(pageSize: 20)
    private var lockedPageControl_02 = Safe4PageControl(pageSize: 20)
    private var proposalPageControl = Safe4PageControl(pageSize: 20)

    private var lockedIds: [BigUInt] = [BigUInt]()
    private var lockedIds_01: [BigUInt] = [BigUInt]()
    private var lockedIds_02: [BigUInt] = [BigUInt]()
    
    @Published private(set) var dataState: ListState = .items
    @Published private(set) var sendState: WithdrawStatus = .normal
    @Published private(set) var hasMoreItems = true
    @Published private(set) var viewItems: [WithdrawItemRecord] = []

    init(service: LockedRecordService, lockedStorage: Safe4LockedRecordStorage) {
        self.service = service
        self.lockedRecoardStorage = lockedStorage
        showCache()
        requestItems(loadMore: false)
    }
}

extension LockedRecordViewModel {
    func withdraw(ids: [BigUInt]) {
        sendState = .loading
        Task {
            do{
                let smallAmount_01 = intersectionUsingSet(lockedIds_01, ids)
                let smallAmount_02 = intersectionUsingSet(lockedIds_02, ids)
                let native = intersectionUsingSet(lockedIds, ids)
                
                if smallAmount_01.count > 0 {
                    let _ = try await service.withdrawByID(type: .smallAmount_01, ids: ids)
                }
                if smallAmount_02.count > 0 {
                    let _ = try await service.withdrawByID(type: .smallAmount_02, ids: ids)
                }
                
                if native.count > 0 {
                    let _ = try await service.withdrawByID(type: .native, ids: ids)
                }
                
                for id in ids {
                    if let index = viewItems.firstIndex(where: { $0.id == id }) {
                        viewItems.remove(at: index)
                    }
                }
                LockedRecordViewModel.saveDidWithdrawIds(ids.map{$0.description})
                
                await MainActor.run {
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
    
    func allWithdraw() {
        guard withdrawEnableIds.count > 0 else{ return }
        guard case .items = dataState else{ return }
        withdraw(ids: withdrawEnableIds)
    }
    
    private func intersectionUsingSet(_ array1: [BigUInt], _ array2: [BigUInt]) -> [BigUInt] {
        let set1 = Set(array1)
        let set2 = Set(array2)
        return Array(set1.intersection(set2))
    }
    
     private func showCache() {
         do{
             let items = try lockedRecoardStorage.allRecords().map{ item in
                 let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
                 return WithdrawItemRecord(lastBlockHeight: lastBlockHeight, record: item.record, info: item.info)
             }
             viewItems = items
             sortItems()
         }catch{}
    }
}

extension LockedRecordViewModel {
    func requestItems(loadMore: Bool) {
        dataState = .loading
        Task {
            do{
                if !loadMore {
                    try lockedRecoardStorage.clear()
                    lockedIds.removeAll()
                    lockedIds_01.removeAll()
                    lockedIds_02.removeAll()
                    
                    async let lockedTotalNum = service.totalLockedNum(type: .native)
                    async let lockedTotalNum_01 = service.totalLockedNum(type: .smallAmount_01)
                    async let lockedTotalNum_02 = service.totalLockedNum(type: .smallAmount_02)
                    async let votedTotalNum = service.getVotedIDNum4Voter()
                    async let proposalTotalNum = service.mineProposalNum()
                    
                    try await lockedPageControl.set(totalNum: Int(lockedTotalNum))
                    try await lockedPageControl_01.set(totalNum: Int(lockedTotalNum_01))
                    try await lockedPageControl_02.set(totalNum: Int(lockedTotalNum_02))
                    try await votedPageControl.set(totalNum: Int(votedTotalNum))
                    try await proposalPageControl.set(totalNum: Int(proposalTotalNum))
                }
                
                guard lockedPageControl.isAbleLoadMore || lockedPageControl_01.isAbleLoadMore || lockedPageControl_02.isAbleLoadMore || votedPageControl.isAbleLoadMore || proposalPageControl.isAbleLoadMore else {
                    DispatchQueue.main.async {
                        self.hasMoreItems = false
                        self.dataState = .items
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
                let uniqueItems = tempItems.reduce(into: [WithdrawItemRecord]()) { result, item in
                     if !result.contains(where: { $0.id == item.id }) {
                         result.append(item)
                     }
                 }
                
                await MainActor.run {
                    viewItems = uniqueItems
                    sortItems()
                    hasMoreItems = true
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
    
    private func Locked_native() async throws -> [WithdrawItemRecord] {
        if lockedPageControl.isAbleLoadMore {
            let lockedIds = try await service.getLockedIDs(type: .native, start: BigUInt(lockedPageControl.start), count: BigUInt(lockedPageControl.currentPageCount))
            self.lockedIds.append(contentsOf: lockedIds)
            let results = try await getRecordInfos(type: .native, ids: lockedIds)
            let items = viewItems(results: results, type: .native)
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
            self.lockedIds_01.append(contentsOf: lockedIds)
            let results = try await getRecordInfos(type: .smallAmount_01, ids: lockedIds)
            let items = viewItems(results: results, type: .smallAmount_01)
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
            self.lockedIds_02.append(contentsOf: lockedIds)
            let results = try await getRecordInfos(type: .smallAmount_02, ids: lockedIds)
            let items = viewItems(results: results, type: .smallAmount_02)
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
            let items = viewItems(results: results, type: .native)
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
            let items = viewItems(results: results.filter{$0.1?.frozenAddr.address != nullAddress}, type: .native)
            if results.count > 0 {
                proposalPageControl.plusPage()
            }
            return items
        }
        return []
    }
    
    private func viewItems(results: [(web3swift.AccountRecord, RecordUseInfo?)], type: web3swift.AccountManager.ContractType) -> [WithdrawItemRecord] {
        let datas = results.filter{$0.0.id != 0}.map { (recordItem, userInfo) in
            let lastBlockHeight = BigUInt(service.lastBlockHeight ?? 0)
            let record = Safe4AccountRecord(record: recordItem)
            var info: Safe4RecordUseInfo? = nil
            if userInfo != nil {
                info = Safe4RecordUseInfo(info: userInfo!)
            }
            // cache Locked Record
            lockedRecoardStorage.save(recoard: Safe4LockedRecord(record: record, info: info))
            return WithdrawItemRecord(lastBlockHeight: lastBlockHeight,
                                      record: record,
                                      info: info
            )
        }
        return datas
    }
    
    private func getRecordInfos(type: web3swift.AccountManager.ContractType, ids: [BigUInt]) async throws -> [(web3swift.AccountRecord, RecordUseInfo?)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo?)] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<(web3swift.AccountRecord, RecordUseInfo?), Error>.self) { taskGroup in
            for id in ids {
                taskGroup.addTask { [self] in
                    do {
                        let info = try await service.getRecordByID(type: type, id: id)
                        var useInfo: RecordUseInfo? = nil
                        if case .native = type {
                            useInfo = try await service.getRecordUseInfo(type: type, id: id)
                        }
                        return .success((info, useInfo))
                    }catch{
                        return .failure(RequestError.getInfo)
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
        Core.shared.userDefaultsStorage.set(value: oldIds, for: LockedRecordWithdrawIdsKey)
    }
}
private let LockedRecordWithdrawIdsKey: String = "safe4_LockedRecord_WithdrawIds_key"


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
    let amount: String
    let unlockHeight: Int
    let releaseHeight: Int?
    let address: String?
    let withdrawEnable: Bool
    let addLockDayEnable: Bool
    
    var idStr: String {
        id.description
    }
    
    init(lastBlockHeight: BigUInt, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        let releaseHeight = BigUInt(info?.releaseHeight ?? "0") ?? BigUInt.zero
        let unlockHeight = BigUInt(record.unlockHeight) ?? BigUInt.zero
        let votedddress = info?.votedAddr ?? nullAddress
        let withdrawEnable = (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) || (unlockHeight.isZero && (releaseHeight < lastBlockHeight))
        let addLockDayEnable = (record.type != 0 || votedddress == nullAddress) ? false : unlockHeight > 0
        let amount = (BigUInt(record.amount) ?? BigUInt.zero).safe4FomattedAmount + " SAFE"
        
        let didWithdrawIds = LockedRecordViewModel.getDidWithdrawIds()
        let isWithdraw = didWithdrawIds.contains(record.id.description)
        self.id = record.id
        self.amount = amount
        self.unlockHeight = Int(unlockHeight)
        self.releaseHeight = releaseHeight.isZero ? nil : Int(releaseHeight)
        self.address = votedddress == nullAddress ? nil : votedddress
        self.withdrawEnable = withdrawEnable && !isWithdraw
        self.addLockDayEnable = addLockDayEnable
    }
    
    init(id: Int, amount: String, unlockHeight: Int, releaseHeight: Int?, address: String?, withdrawEnable: Bool, addLockDayEnable: Bool) {
        self.id = id
        self.amount = amount
        self.unlockHeight = unlockHeight
        self.releaseHeight = releaseHeight
        self.address = address
        self.withdrawEnable = withdrawEnable
        self.addLockDayEnable = addLockDayEnable
    }
    
    static func == (lhs: WithdrawItemRecord, rhs: WithdrawItemRecord) -> Bool {
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount &&
        lhs.unlockHeight == rhs.unlockHeight &&
        lhs.releaseHeight == rhs.releaseHeight &&
        lhs.address == rhs.address
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(amount)
        hasher.combine(unlockHeight)
        hasher.combine(releaseHeight)
        hasher.combine(address)
    }
}
