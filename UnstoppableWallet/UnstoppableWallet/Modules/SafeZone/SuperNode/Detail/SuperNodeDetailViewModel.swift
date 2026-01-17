import Foundation
import UIKit
import HsToolKit
import BigInt
import web3swift
import Web3Core
import HsExtensions
import RxSwift
import RxRelay
import RxCocoa

class SuperNodeDetailViewModel {

    private(set) var viewItems = [SuperNodeDetailViewModel.ViewItem]()
    private(set) var voterItems = [SuperNodeDetailViewModel.VoterInfoItem]()
    private(set) var lockRecordItems = [SuperNodeDetailViewModel.LockRecoardItem]()
    private let userDefaultsStorage = UserDefaultsStorage()
    private let superNodeLockRecordStorage: SuperNodeLockRecordStorage
    private(set) var lockRecordIsLoading = false
    private(set) var hasMoreRecords: Bool = true

    private var safe4Page = Safe4PageControl(pageSize: 30)
    private var votedPageControl = Safe4PageControl(pageSize: 30)
    private var lockedPageControl = Safe4PageControl(pageSize: 30)
    private var proposalPageControl = Safe4PageControl(pageSize: 30)
    
    private let nodeViewItem: SuperNodeViewModel.ViewItem
    private let service: SuperNodeDetailService
    private var isEnabledSend = true

    private var stateRelay = PublishRelay<SuperNodeDetailViewModel.State>()
    private(set) var state: SuperNodeDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(nodeViewItem: SuperNodeViewModel.ViewItem, service: SuperNodeDetailService, superNodeLockRecordStorage: SuperNodeLockRecordStorage) {
        self.nodeViewItem = nodeViewItem
        self.service = service
        self.superNodeLockRecordStorage = superNodeLockRecordStorage
        viewItems = nodeViewItem.info.founders.map {ViewItem(info: $0, isSelf: service.address.lowercased() == $0.addr.address.lowercased())}
    }
}

extension SuperNodeDetailViewModel {
    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task { [service] in
            do{
                let address = nodeViewItem.info.addr
                if !loadMore {
                    let totalNum = try await service.getVoterNum(address: address)
                    safe4Page.set(totalNum: Int(totalNum))
                }
                guard voterItems.count < safe4Page.totalNum else { return }
                let voteRetInfo = try await service.getVoters(address: address, page: safe4Page)
                safe4Page.plusPage()
                let results = zip(voteRetInfo.addrs, voteRetInfo.voteNums).map { VoterInfoItem(address: $0.address, voteNum: $1, isSelf: service.address.lowercased() == $0.address.lowercased()) }
                voterItems.append(contentsOf: results)
                state = .completed(datas: voterItems)
            }catch{
                state = .failed(error: "")
            }
        }
    }
    
    @MainActor
    private func showCache() {
        do {
            let items = try superNodeLockRecordStorage.allRecords().map {
                recordItem(isExist: $0.isSuperNode, isVoted: $0.isVoted, record: $0.record.transform(), info: ($0.info?.transform())!)
            }
            if items.count > 0 {
                showLockRecoard(tempItems: items)
            }
        }catch{
            print("")
        }
        
    }
    
    func requestLockRecords(loadMore: Bool) {
        
        Task { [service] in
            do{
                if !loadMore {
                    await showCache()
                    lockRecordIsLoading = true
                    let cacheCount = try superNodeLockRecordStorage.allRecords().count
                    async let lockedTotalNum = service.totalLockedNum(type: .native)
                    async let votedTotalNum = service.getVotedIDNum4Voter()
                    async let proposalTotalNum = service.mineProposalNum()
                    
                    try await lockedPageControl.set(totalNum: Int(lockedTotalNum))
                    try await votedPageControl.set(totalNum: Int(votedTotalNum))
                    try await proposalPageControl.set(totalNum: Int(proposalTotalNum))
                    
                    let total = try await( lockedTotalNum + votedTotalNum + proposalTotalNum )
                    if total > 0, cacheCount == total {
                        hasMoreRecords = false
                    }else if total > 0 {
                        hasMoreRecords = true
                    }
                }
                
                guard lockedPageControl.isAbleLoadMore || votedPageControl.isAbleLoadMore || proposalPageControl.isAbleLoadMore else {
                    await showLockRecoard(tempItems: [])
                    lockRecordIsLoading = false
                    hasMoreRecords = false
                    return
                }
                
                lockRecordIsLoading = true
                
                var tempItems = [SuperNodeDetailViewModel.LockRecoardItem]()
                                
                async let items_0 = locked()
                async let items_1 = voted()
                async let items_2 = proposal()
                tempItems = try await (items_0 + items_1 + items_2)
                

                await showLockRecoard(tempItems: tempItems)
            }catch{
                await showLockRecoard(tempItems: [])
                lockRecordIsLoading = false
            }
        }
    }
    
    @MainActor
    private func showLockRecoard(tempItems: [SuperNodeDetailViewModel.LockRecoardItem]) {

        var tempArray = tempItems.filter{!$0.record.amount.isZero}
        tempArray.append(contentsOf: lockRecordItems)
        
        var uniqueItems = tempArray.reduce(into: [LockRecoardItem]()) { result, item in
            if !result.contains(where: { $0.record.id == item.record.id }) {
                 result.append(item)
             }
         }
        
        uniqueItems.sort {
            if $0.isEnabledSlect != $1.isEnabledSlect {
                return $0.isEnabledSlect
            } else {
                return $0.record.id < $1.record.id
            }
        }
        lockRecordItems = uniqueItems
        state = .lockRecoardCompleted(datas: uniqueItems)
        lockRecordIsLoading = false
    }
    
    private func locked() async throws -> [LockRecoardItem] {
        if lockedPageControl.isAbleLoadMore {
            let lockedIds = try await service.getLockedIDs(type: .native, start: BigUInt(lockedPageControl.start), count: BigUInt(lockedPageControl.currentPageCount))
            let results = try await getRecordInfo(ids: lockedIds, isVoted: false)
            if results.count > 0 {
                lockedPageControl.plusPage()
            }
            return results
        }
        return []
    }
    
    private func voted() async throws -> [LockRecoardItem] {
        if votedPageControl.isAbleLoadMore {
            let votedIds = try await service.getVotedIDs4Voter(start: BigUInt(votedPageControl.start), count: BigUInt(votedPageControl.currentPageCount))
            let results = try await getRecordInfo(ids: votedIds, isVoted: true)
            if results.count > 0 {
                votedPageControl.plusPage()
            }
            return results
        }
        return []
    }

    private func proposal() async throws -> [LockRecoardItem] {
        if proposalPageControl.isAbleLoadMore {
            let proposalIds = try await service.mineProposalIds(start: BigUInt(proposalPageControl.start), count: BigUInt(proposalPageControl.currentPageCount))
            var ids = [BigUInt]()
            for id in proposalIds {
                let rewardIDs =  try await service.getProposalRewardIDs(id: id)
                ids.append(contentsOf: rewardIDs)
            }
            let results = try await getRecordInfo(ids: ids, isVoted: false)
            if results.count > 0 {
                proposalPageControl.plusPage()
            }
            return results
        }
        return []
    }
    
    private func getRecordInfo(ids: [BigUInt], isVoted: Bool) async throws  -> [LockRecoardItem] {
        var results: [LockRecoardItem] = []
        var errors: [Error] = []
        
        await withTaskGroup(of: Result<LockRecoardItem, Error>.self) { taskGroup in
            for id in ids {
                taskGroup.addTask { [self, service] in
                    do {
                        let record = try await service.getRecordByID(id: id)
                        let info = try await service.getRecordUseInfo(id: id)
                        var isExist: Bool = false
                        if !isVoted {
                            isExist = try await service.exist(address: info.frozenAddr)
                        }
                        let cacheItem = SuperNodeLockRecord(isSuperNode: isExist, isVoted: isVoted, record: record, info: info)
                        superNodeLockRecordStorage.save(recoard: cacheItem)
                        let item = recordItem(isExist: isExist, isVoted: isVoted, record: record, info: info)
                        return .success(item)
                    }catch{
                        return .failure(LockRecoardError.getInfo)
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
    
    private func recordItem(isExist: Bool, isVoted: Bool, record: web3swift.AccountRecord, info: RecordUseInfo) -> LockRecoardItem {
        let catchVotedIds = votedIdsCatch()
        var isUsed: Bool = false
        if let catchVotedIds, catchVotedIds.contains(record.id.description) {
            isUsed = true
        }
        let lastBlockHeight = service.lastBlockHeight() ?? .zero
        let isHigher = lastBlockHeight > info.releaseHeight
        let releaseHeight = info.releaseHeight
        let unlockHeight = record.unlockHeight
        let withdrawEnable = isVoted ? (releaseHeight.isZero && (unlockHeight < lastBlockHeight)) || (unlockHeight.isZero && (releaseHeight < lastBlockHeight)) : false
        let isRemoveVoteEnable = isVoted ? (releaseHeight.isZero ? false : releaseHeight < lastBlockHeight) : false

        let isValid = (record.amount.safe4ToDecimal() ?? 0) >= 1
        let isEnabledSlect: Bool
        if isVoted {
            isEnabledSlect = isUsed ? false : isValid && (withdrawEnable || isRemoveVoteEnable)
        }else {
            isEnabledSlect = isUsed ? false : isValid && !isExist && isHigher
        }
        let item = LockRecoardItem(record: record, info: info, isEnabledSlect: isEnabledSlect)
        return item
    }
}
extension SuperNodeDetailViewModel {
    
    func safeVote(amount: Decimal) {
        Task { [service] in
            do{
                let value = BigUInt((amount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
                guard isEnabledSend else { return }
                isEnabledSend = false
                let _ = try await service.voteOrApprovalWithAmount(dstAddr: nodeViewItem.info.addr, value: value)
                state = .voteCompleted
                isEnabledSend = true
            }catch{
                isEnabledSend = true
                state = .failed(error: "safe_zone.safe4.vote.fail".localized)
            }
        }
    }
    
    func lockRecordVote() {
        let ids = lockRecordItems.filter{$0.isSlected == true}.map{$0.record.id}
        Task { [service] in
            do{
                guard isEnabledSend else { return }
                isEnabledSend = false
                let _ = try await service.voteOrApproval(dstAddr: nodeViewItem.info.addr, recordIDs: ids)
                catchVotedLockRecordIds(ids: ids)
                isEnabledSend = true
                state = .voteCompleted
            }catch{
                isEnabledSend = true
                state = .failed(error: "safe_zone.safe4.vote.fail".localized)
            }
        }
    }
    
    func joinPartner(value: Float){
        Task { [service] in
            do{
                let value = BigUInt((Decimal(Double(value)) * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
                guard isEnabledSend else { return }
                isEnabledSend = false
                let _ = try await service.appendRegister(value: value, dstAddr: nodeViewItem.info.addr)
                isEnabledSend = true
                state = .partnerCompleted
            }catch{
                isEnabledSend = true
                state = .failed(error: "safe_zone.safe4.partner.join.failed".localized)
            }
        }
    }
    
    private var catchKey: String {
        "\(nodeViewItem.info.addr.address)_votedIds_Key"
    }
    
    private func catchVotedLockRecordIds(ids: [BigUInt]) {
        userDefaultsStorage.set(value: ids.map{$0.description}, for: catchKey)
    }
    
    private func votedIdsCatch() -> [String]? {
        userDefaultsStorage.value(for: catchKey)
    }
    
    private func removeCatch() {
        userDefaultsStorage.set(value: nil as [String]?, for: catchKey)
    }
}

extension SuperNodeDetailViewModel {
    func refresh() {
        voterItems.removeAll()
        requestInfos(loadMore: false)
        requestLockRecords(loadMore: false)
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        requestInfos(loadMore: true)
    }
    
    func loadMoreLockRecord() {
        guard lockRecordIsLoading == false else { return }
        requestLockRecords(loadMore: true)
    }
    
    @MainActor
    func selectAllLockRecord(_ iselected: Bool) {
        for item in lockRecordItems {
            item.update(isSelected: iselected)
        }
        showLockRecoard(tempItems:[])
    }
}

extension SuperNodeDetailViewModel {

    var balance: String {
        "\(service.balance ?? 0.00) SAFE"
    }
    
    var balanceDriver: Driver<Decimal?> {
        service.balanceDriver
    }
    
    var detailInfo: SuperNodeViewModel.ViewItem {
        nodeViewItem
    }
    
    var stateDriver: Observable<SuperNodeDetailViewModel.State> {
        stateRelay.asObservable()
    }
    
    var selectedLockRecoardItems: [SuperNodeDetailViewModel.LockRecoardItem] {
        lockRecordItems.filter{$0.isSlected == true}
    }
    
    var sendData: SuperNodeSendData {
        SuperNodeSendData(name: nodeViewItem.info.name, address: nodeViewItem.info.addr.address, ENODE: nodeViewItem.info.enode, desc: nodeViewItem.info.description, amount: 0)
    }
}

extension SuperNodeDetailViewModel {
    enum State {
        case loading
        case completed(datas: [SuperNodeDetailViewModel.VoterInfoItem])
        case voteCompleted
        case partnerCompleted
        case lockRecoardCompleted(datas: [SuperNodeDetailViewModel.LockRecoardItem])
        case failed(error: String)
    }
}

extension SuperNodeDetailViewModel {
    
    struct ViewItem {
        let info: SuperNodeMemberInfo
        let isSelf: Bool
        
        var id: String {
            info.lockID.description
        }
        
        var address: String {
            info.addr.address
        }
        
        var safeAmount: String {
            return info.amount.safe4FomattedAmount + " SAFE"
        }
    }
    
    struct VoterInfoItem {
        let address: String
        let voteNum: BigUInt
        let isSelf: Bool
        
        var amount: String {
            return voteNum.safe4FomattedAmount + " SAFE"
        }
    }
    
    class LockRecoardItem {
        let record: web3swift.AccountRecord
        var info: RecordUseInfo
        var isSlected: Bool = false
        var isEnabledSlect: Bool

        init(record: web3swift.AccountRecord, info: RecordUseInfo, isEnabledSlect: Bool) {
            self.record = record
            self.info = info
            self.isEnabledSlect = isEnabledSlect
        }
        
        func update(isSelected: Bool) {
            guard isEnabledSlect else { return }
            self.isSlected = isSelected
        }
    }
    
    enum VoteType {
        case safe(amount: Decimal)
        case lockRecord(items: [SuperNodeDetailViewModel.LockRecoardItem])
    }
    
    enum ViewType {
        case Detail
        case JoinPartner
        case Vote
    }
    
    enum LockRecoardError: Error {
        case getInfo
    }
}


