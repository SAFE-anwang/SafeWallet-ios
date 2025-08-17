import Combine
import UIKit
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

class LockedRecoardViewModel: ObservableObject {
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let service: LockedRecoardService
    var votedPageControl = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)
    var lockedPageControl = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)
    var proposalPageControl = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)

    @Published private(set) var dataState: State = .loading
    @Published private(set) var sendState: WithdrawStatus = .normal
    @Published var hasMoreItems = true
    @Published var isLoadingMore = false
    @Published private(set) var viewItems: [WithdrawItem] = []
        
    init(service: LockedRecoardService) {
        self.service = service
        requestItems(loadMore: false)
    }

}

extension LockedRecoardViewModel {
    func withdraw(id: BigUInt) {
        sendState = .loading
        Task {
            do{
                let _ = try await service.withdrawByID(id: id)
                sendState = .success(message: "safe_zone.safe4.withdraw".localized + "transactions.types.outgoing".localized)
            }catch{
                sendState = .failed(error: "settings.personal_support.failed".localized)
            }
        }
    }

    func loadMore() {
        if case .loading = dataState {
            return
        }
        requestItems(loadMore: true)
    }
}

extension LockedRecoardViewModel {
    func requestItems(loadMore: Bool) {
        dataState = .loading
        Task {
            do{
                if !loadMore {
                    let lockedTotalNum = try await service.totalLockedNum()
                    let votedTotalNum = try await service.getVotedIDNum4Voter()
                    let proposalTotalNum = try await service.mineProposalNum()
                    
                    lockedPageControl.set(totalNum: Int(lockedTotalNum))
                    votedPageControl.set(totalNum: Int(votedTotalNum))
                    proposalPageControl.set(totalNum: Int(proposalTotalNum))
                }
                
                guard lockedPageControl.totalNum > 0 || votedPageControl.totalNum > 0 || proposalPageControl.totalNum > 0 else { return  dataState = .completed }
                guard viewItems.count < lockedPageControl.totalNum + votedPageControl.totalNum + proposalPageControl.totalNum else {
                    await MainActor.run {
                        hasMoreItems = false
                    }
                    return
                }
                var ids = [BigUInt]()
                if lockedPageControl.totalNum > 0 {
                    let lockedIds = try await service.getLockedIDs(start: BigUInt(lockedPageControl.start), count: BigUInt(lockedPageControl.currentPageCount))
                    ids.append(contentsOf: lockedIds)
                }
                
                if votedPageControl.totalNum > 0 {
                    let votedIds = try await service.getVotedIDs4Voter(start: BigUInt(votedPageControl.start), count: BigUInt(votedPageControl.currentPageCount))
                    ids.append(contentsOf: votedIds)
                }
                
                if proposalPageControl.totalNum > 0 {
                    async let proposalIds = service.mineProposalIds(start: BigUInt(proposalPageControl.start), count: BigUInt(proposalPageControl.currentPageCount))
                    let items = try await mineProposalWithdrawItems(ids: proposalIds)
                    viewItems.append(contentsOf: items)
                }
                
                var tempIds = Set(ids)
                tempIds.subtract(Set(viewItems.map{$0.id}))
                let results = try await getRecordInfos(ids: Array(tempIds))
                
                let datas = results.map { WithdrawItem(id: $0.0.id,
                                                       amount: $0.0.amount.safe4FomattedAmount + " SAFE",
                                                       unlockHeight: $0.0.unlockHeight.isZero ? $0.1.releaseHeight : $0.0.unlockHeight,
                                                       releaseHeight: $0.1.releaseHeight,
                                                       address: $0.1.votedAddr.address == nullAddress ? nil : $0.1.votedAddr.address,
                                                       withdrawEnable: ($0.0.unlockHeight.isZero ? $0.1.releaseHeight : $0.0.unlockHeight) < (service.lastBlockHeight ?? 0),
                                                       addLockDayEnable: $0.1.votedAddr.address != nullAddress && (!$0.0.unlockHeight.isZero || !$0.1.releaseHeight.isZero)
                                          )
                }
                
                
                await MainActor.run {
                    if loadMore {
                        isLoadingMore = false
                    }
                    viewItems.append(contentsOf: datas)
                    viewItems.sort(by: {Int($0.id) < Int($1.id)})
                    dataState = .completed
                }
            }catch{
                if viewItems.isEmpty {
                    dataState = .failed(error: nil)
                }
            }
        }
    }
    
    func checkIfShouldLoadMore(offset: CGFloat) {
        let loadThreshold: CGFloat = 50
        
        if offset > loadThreshold, hasMoreItems {
            isLoadingMore = true
            loadMore()
        }
    }
    
    private func getRecordInfos(ids: [BigUInt]) async throws -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo)] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<(web3swift.AccountRecord, RecordUseInfo), Error>.self) { taskGroup in
            for id in ids {
                taskGroup.addTask { [self] in
                    do {
                        let useInfo = try await service.getRecordUseInfo(id: id)
                        let info = try await service.getRecordByID(id: id)
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
        if results.count > 0 {
            lockedPageControl.plusPage()
            votedPageControl.plusPage()
            proposalPageControl.plusPage()
        }
        return results
    }
    
    private func mineProposalWithdrawItems(ids: [BigUInt]) async throws -> [WithdrawItem] {
        var items = [WithdrawItem]()
        for id in ids {
            let info = try await service.getInfo(id: id)
            let rewardIDs =  try await service.getProposalRewardIDs(id: id)
            for rewardId in rewardIDs {
                let item = WithdrawItem(id: rewardId,
                                        amount: (info.payAmount / info.payTimes).safe4FomattedAmount + " SAFE",
                                        unlockHeight: info.updateHeight,
                                        releaseHeight: .zero,
                                        address: nullAddress,
                                        withdrawEnable: true,
                                        addLockDayEnable: false
                )
                items.append(item)
            }
        }
        return items
    }
}
extension LockedRecoardViewModel {
    enum RequestError: Error {
        case pageError
        case getInfo
        case withdrawError
    }
    
    enum State: Equatable {
        case loading
        case completed
        case failed(error: String?)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.completed, .completed): return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
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
    
    struct WithdrawItem: Equatable {
        let id: BigUInt
        let amount: String
        let unlockHeight: BigUInt
        let releaseHeight: BigUInt
        let address: String?
        let withdrawEnable: Bool
        let addLockDayEnable: Bool
        
        var idStr: String {
            id.description
        }
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }
}
