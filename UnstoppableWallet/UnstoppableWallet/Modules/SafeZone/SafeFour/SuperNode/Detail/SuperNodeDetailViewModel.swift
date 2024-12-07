import Foundation
import UIKit
import HsToolKit
import BigInt
import web3swift
import Web3Core
import HsExtensions
import ThemeKit
import RxSwift
import RxRelay
import RxCocoa

class SuperNodeDetailViewModel {

    private(set) var viewItems = [SuperNodeDetailViewModel.ViewItem]()
    private(set) var voterItems = [SuperNodeDetailViewModel.VoterInfoItem]()
    private(set) var lockRecordItems = [SuperNodeDetailViewModel.LockRecoardItem]()
    private let userDefaultsStorage = UserDefaultsStorage()
    
    private(set) var totalIDs = [BigUInt]()

    private(set) var lockRecordIsLoading = false

    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: false)
    private var votedIDsSafe4Page = Safe4PageControl(initCount: 100, totalNum: 0, page: 0, isReverse: false)
    private var lockRecordSafe4Page = Safe4PageControl(initCount: 100, totalNum: 0, page: 0, isReverse: false)
    
    private let nodeViewItem: SuperNodeViewModel.ViewItem
    private let service: SuperNodeDetailService
    
    private var isEnabledSend = true

    private var stateRelay = PublishRelay<SuperNodeDetailViewModel.State>()
    private(set) var state: SuperNodeDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(nodeViewItem: SuperNodeViewModel.ViewItem, service: SuperNodeDetailService) {
        self.nodeViewItem = nodeViewItem
        self.service = service
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
    
    private func requestVotedIDs() async throws -> [BigUInt] {
        let totalNum = try await service.getVotedIDNum4Voter()
        votedIDsSafe4Page.set(totalNum: Int(totalNum))
        guard totalNum > 0 else {return [] }
        guard votedIDsSafe4Page.totalNum > 0 else { return []}
        
        var results: [BigUInt] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<[BigUInt], Error>.self) { taskGroup in
            for page in votedIDsSafe4Page.pageArray {
                taskGroup.addTask { [self] in
                    do {
                        guard let start = page.first else{ return .failure(LockRecoardError.getInfo) }
                        let ids = try await service.getVotedIDs4Voter(start: BigUInt(start), count: BigUInt(page.count))
                        return .success(ids)
                    }catch{
                        return .failure(LockRecoardError.getInfo)
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
        return results
    }
    
    private func requestLockRecords(loadMore: Bool) {
        lockRecordIsLoading = true
        Task { [service] in
            do{
                if !loadMore {
                    lockRecordSafe4Page.set(totalNum: 1000)
                }
                let votedIDs = try await requestVotedIDs()
                let totalIDs = try await service.getTotalIDs(page: lockRecordSafe4Page)
                guard totalIDs.count > 0 else{ return state = .lockRecoardCompleted(datas: [])}
                lockRecordSafe4Page.plusPage()
                
                var results: [LockRecoardItem] = []
                var errors: [Error] = []
                let catchVotedIds = votedIdsCatch()
                if let ids = catchVotedIds {
                    if Set(ids).isSubset(of: Set(votedIDs.map{$0.description})) {
                        removeCatch()
                    }
                }
                await withTaskGroup(of: Result<LockRecoardItem, Error>.self) { taskGroup in
                    for id in totalIDs {
                        taskGroup.addTask {
                            do {
                                let info = try await service.getRecordByID(id: id)
                                var isVoted = votedIDs.contains(id)
                                if let catchVotedIds, catchVotedIds.contains(id.description) {
                                    isVoted = true
                                }
                                let recordUseInfo = try await service.getRecordUseInfo(id: id)
                                let isExist = try await service.exist(address: recordUseInfo.frozenAddr)
                                var isHigher = false
                                if let heihgt = service.lastBlockHeight() {
                                    isHigher = heihgt > recordUseInfo.releaseHeight
                                }
                                let item = LockRecoardItem(info: info, isHigher: isHigher, isVoted: isVoted, isSuperNode: isExist, recordUseInfo: recordUseInfo)
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
                lockRecordItems.append(contentsOf: results)
                lockRecordItems.sort{$0.info.id > $1.info.id}
                state = .lockRecoardCompleted(datas: lockRecordItems)
                lockRecordIsLoading = false
            }catch{
                state = .lockRecoardCompleted(datas: lockRecordItems)
                lockRecordIsLoading = false
            }
        }
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
        let ids = lockRecordItems.filter{$0.isSlected == true}.map{$0.info.id}
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
    
    func selectAllLockRecord(_ iselected: Bool) {
        for item in lockRecordItems {
            item.update(isSelected: iselected)
        }
        state = .lockRecoardCompleted(datas: lockRecordItems)
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
        let info: web3swift.AccountRecord
        var isHigher: Bool = false
        var isVoted: Bool = false
        var isSlected: Bool = false
        var isSuperNode: Bool = false
        var recordUseInfo: RecordUseInfo
        
        init(info: web3swift.AccountRecord, isHigher: Bool, isVoted: Bool, isSuperNode: Bool, recordUseInfo: RecordUseInfo) {
            self.info = info
            self.isHigher = isHigher
            self.isVoted = isVoted
            self.isSuperNode = isSuperNode
            self.recordUseInfo = recordUseInfo
        }
        
        func update(isVoted: Bool) {
            self.isVoted = isVoted
        }
        
        func update(isSelected: Bool) {
            guard isEnabled else { return }
            self.isSlected = isSelected
        }
        
        var isEnabled: Bool {
            let isValid = (info.amount.safe4ToDecimal() ?? 0) >= 1
            guard !isVoted && isValid && !isSuperNode && isHigher else {return false}
            return true
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
