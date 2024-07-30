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
    private(set) var votedIDs = [BigUInt]()
    private(set) var lockRecordIsLoading = false
    private(set) var nodeType: Safe4NodeType

    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: false)
    private var votedIDsSafe4Page = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)
    private var lockRecordSafe4Page = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)
    
    private let nodeViewItem: SuperNodeViewModel.ViewItem
    private let service: SuperNodeDetailService
    
    private var isEnabledSend = true

    private var stateRelay = PublishRelay<SuperNodeDetailViewModel.State>()
    private(set) var state: SuperNodeDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(nodeType: Safe4NodeType, nodeViewItem: SuperNodeViewModel.ViewItem, service: SuperNodeDetailService) {
        self.nodeType = nodeType
        self.nodeViewItem = nodeViewItem
        self.service = service
        viewItems = nodeViewItem.info.founders.map {ViewItem(info: $0)}
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
                let results = zip(voteRetInfo.addrs, voteRetInfo.voteNums).map { VoterInfoItem(address: $0.address, voteNum: $1) }
                voterItems.append(contentsOf: results)
                state = .completed(datas: voterItems)
            }catch{
                state = .failed(error: "")
            }
        }
    }
    
    private func requestLockRecords(loadMore: Bool) {
        lockRecordIsLoading = true
        Task { [service] in
            do{
                if !loadMore {
                    lockRecordSafe4Page.set(totalNum: 1000)
                    let totalNum = try await service.getVotedIDNum4Voter()
                    votedIDsSafe4Page.set(totalNum: Int(totalNum))
                    
                    repeat {
                        guard votedIDsSafe4Page.totalNum > 0 else { break }
                        guard votedIDs.count < safe4Page.totalNum else { break }
                        let ids = try await service.getVotedIDs4Voter(page: votedIDsSafe4Page)
                        if ids.count > 0 { votedIDsSafe4Page.plusPage() }
                        votedIDs.append(contentsOf: ids)
                    } while votedIDs.count < votedIDsSafe4Page.totalNum
                }

                let totalIDs = try await service.getTotalIDs(page: lockRecordSafe4Page)
                guard totalIDs.count > 0 else{ return }
                lockRecordSafe4Page.plusPage()
                var results: [LockRecoardItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<LockRecoardItem, Error>.self) { taskGroup in
                    for id in totalIDs {
                        taskGroup.addTask { [self] in
                            do {
                                async let info = try service.getRecordByID(id: id)
                                let isVoted = self.votedIDs.contains(id)
                                let recordUseInfo = try await service.getRecordUseInfo(id: id)
                                async let isExist = try service.exist(address: recordUseInfo.frozenAddr)
                                var isLess = false
                                if let heihgt = service.lastBlockHeight() {
                                    isLess = heihgt < recordUseInfo.releaseHeight
                                }
                                let item = try await LockRecoardItem(info: info, isLess: isLess, isVoted: isVoted, isSuperNode: isExist, recordUseInfo: recordUseInfo)
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
                results.sort{$0.info.id > $1.info.id}
                lockRecordItems.append(contentsOf: results)
                state = .lockRecoardCompleted(datas: lockRecordItems)
                lockRecordIsLoading = false
            }catch{
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
                state = .failed(error: "投票失败！")
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
                isEnabledSend = true
                state = .voteCompleted
            }catch{
                isEnabledSend = true
                state = .failed(error: "投票失败！")
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
                state = .failed(error: "成为合伙人失败！")
            }
        }
    }
}

extension SuperNodeDetailViewModel {
    func refresh() {
        votedIDs.removeAll()
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
        
        var amount: String {
            return voteNum.safe4FomattedAmount + " SAFE"
        }
    }
    
    class LockRecoardItem {
        let info: web3swift.AccountRecord
        var isLess: Bool = false
        var isVoted: Bool = false
        var isSlected: Bool = false
        var isSuperNode: Bool = false
        var recordUseInfo: RecordUseInfo
        
        init(info: web3swift.AccountRecord, isLess: Bool, isVoted: Bool, isSuperNode: Bool, recordUseInfo: RecordUseInfo) {
            self.info = info
            self.isLess = isLess
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
            let isValid = (info.amount.safe4ToDecimal() ?? 0) < 1
            if isVoted || isValid || isSuperNode || isLess {return false}
            return true
        }
    }
    
    enum LockRecoardError: Error {
        case getInfo
    }
}
