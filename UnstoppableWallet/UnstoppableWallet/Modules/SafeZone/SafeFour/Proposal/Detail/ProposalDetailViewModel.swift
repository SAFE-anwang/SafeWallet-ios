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
import ThemeKit

class ProposalDetailViewModel {
    private let servie: ProposalDetailService
    private var safe4Page = Safe4PageControl(initCount: 100)
    private var stateRelay = PublishRelay<ProposalDetailViewModel.State>()
    private var viewItems = [ProposalDetailViewModel.ViewItem]()
    private let infoItem: ProposalViewModel.ViewItem
    private(set) var state: ProposalDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(infoItem: ProposalViewModel.ViewItem, servie: ProposalDetailService) {
        self.infoItem = infoItem
        self.servie = servie
    }
}

extension ProposalDetailViewModel {
    
    func vote(result: VoteState) {
        Task {
            do {
                let id = infoItem.info.id
                let txId = try await servie.vote(id: id, voteResult: result.voteResult)
                state = .voteCompleted
            }catch {
                if let nodeError = error as? Web3Core.Web3Error {
                    if case let .nodeError( desc) = nodeError {
                        state = .failed(error: "当前账户不是排名前49且在线的超级节点，不能对提案进行投票")
                    }
                }
            }
        }
    }
    
    func isAbleVote() {
        Task {
            do{
                guard infoItem.status == .voting else { return }
                try await servie.isAbleVote()
            }catch{}
        }
    }
}
extension ProposalDetailViewModel {

    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task(priority: .userInitiated) { [servie, infoItem] in
            do{
                let id = infoItem.info.id
                if !loadMore {
                    let totalNum = try await servie.getVoterNum(id: id)
                    safe4Page.set(totalNum: Int(totalNum))
                }
                guard safe4Page.totalNum > 0 else { return  state = .completed(datas: []) }
                guard viewItems.count < safe4Page.totalNum else { return }
                
                let infos = try await servie.getVoteInfo(id: id, page: safe4Page)
                let results = infos.map {ViewItem(info: $0)}
                if results.count > 0 { safe4Page.plusPage() }
                viewItems.append(contentsOf: results)
                state = .completed(datas: viewItems)
 
            }catch{
                if let processingError = error as? Web3Core.Web3Error {
                    if case let .processingError( desc) = processingError {
                        state = .failed(error: desc)
                    }
                }
            }
        }
    }
}

extension ProposalDetailViewModel {
    
    func refresh() {
        viewItems.removeAll()
        isAbleVote()
        requestInfos(loadMore: false)
    }
    
    func loadMore() {
        if case .loading = state { return }
        requestInfos(loadMore: true)
    }
    
    var voteTotalNum: Int {
        safe4Page.totalNum
    }
    
    var detailInfo: ProposalViewModel.ViewItem {
        infoItem
    }
    
    func voteNum(state: VoteState) -> Int {
        viewItems.filter{$0.voteState == state}.count
    }
    
    var voteState: ProposalViewModel.ProposalState {
        infoItem.status
    }
    
    var votedResult: VoteState? {
        viewItems.filter{ $0.info.voter.address.lowercased() == servie.address.lowercased()}.first?.voteState
    }
    
    var voteStateDesc: String {
        "合计\(voteTotalNum)票 同意\(voteNum(state: .passed))票 拒绝\(voteNum(state: .abstain))票 弃权\(voteNum(state: .refuse))票"
    }
}

extension ProposalDetailViewModel {
    
    var stateDriver: Observable<ProposalDetailViewModel.State> {
        stateRelay.asObservable()
    }
    
    var isAbleVoteDriver: Driver<Bool> {
        servie.isAbleVoteDriver
    }
}

extension ProposalDetailViewModel {
    
    enum State {
        case loading
        case completed(datas: [ProposalDetailViewModel.ViewItem])
        case voteCompleted
        case failed(error: String)
    }
    
    struct ViewItem {
        let info: ProposalVoteInfo
        
        var voteState: VoteState? {
            switch info.voteResult {
            case 1:
                return .passed
            case 2:
                return .refuse
            case 3:
                return .abstain

            default: return nil
            }
        }
    }
    
    enum VoteState {
        case passed
        case refuse
        case abstain

        var title: String {
            switch self {
            case .passed:
                return "safe_zone.safe4.vote.passed".localized
            case .refuse:
                return "safe_zone.safe4.vote.refuse".localized
            case .abstain:
                return "safe_zone.safe4.vote.abstain".localized
            }
        }
        
        var color: UIColor {
            switch self {
            case .passed:
                return  .themeRemus
            case .refuse:
                return  .themeLucian
            case .abstain:
                return .themeElena
            }
        }
        
        var image: String {
            switch self {
            case .passed:
                return "circle_check_24"
            case .refuse:
                return "refuse"
            case .abstain:
                return "abstain"
            }
        }
        
        var voteResult: BigUInt {
            switch self {
            case .passed:
                return 1
            case .refuse:
                return 2
            case .abstain:
                return 3
            }
        }
    }
}
