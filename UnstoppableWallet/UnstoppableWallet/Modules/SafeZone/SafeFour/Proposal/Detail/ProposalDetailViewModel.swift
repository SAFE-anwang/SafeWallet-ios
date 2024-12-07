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
    private let catch_key = "voted_Key"
    private let servie: ProposalDetailService
    private var safe4Page = Safe4PageControl(initCount: 100)
    private var stateRelay = PublishRelay<ProposalDetailViewModel.State>()
    private var viewItems = [ProposalDetailViewModel.ViewItem]()
    private let infoItem: ProposalViewModel.ViewItem
    private let userDefaultsStorage = UserDefaultsStorage()
    private(set) var state: ProposalDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    var isAbleVote: Bool = false {
        didSet {
            if isAbleVote != oldValue {
                isAbleVoteRelay.accept(isAbleVote)
            }
        }
    }
    private var isAbleVoteRelay = BehaviorRelay<Bool>(value: false)

    init(infoItem: ProposalViewModel.ViewItem, servie: ProposalDetailService) {
        self.infoItem = infoItem
        self.servie = servie
        getAbleVote()
    }
}

extension ProposalDetailViewModel {
    
    func vote(result: VoteState) {
        Task {
            do {
                let id = infoItem.info.id
                let txId = try await servie.vote(id: id, voteResult: result.voteResult)
                catchVoted(id: id.description)
                state = .voteCompleted
            }catch {
                if let nodeError = error as? Web3Core.Web3Error {
                    if case let .nodeError( desc) = nodeError {
                        state = .failed(error: "safe_zone.safe4.proposal.vote.node.super.cannot".localized)
                    }
                }
            }
        }
    }
    
    func getAbleVote() {
        Task {
            do {
                isAbleVote = try await servie.isAbleVote()
            } catch {}
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

private extension ProposalDetailViewModel {
    
    private var catchKey: String {
        "\(infoItem.info.id)_proposal_Key"
    }
    
    private func catchVoted(id: String) {
        userDefaultsStorage.set(value: id, for: catchKey)
    }
    
    private func votedIdCatch() -> String? {
        userDefaultsStorage.value(for: catchKey)
    }
    
    private func removeCatch() {
        userDefaultsStorage.set(value: nil as String?, for: catchKey)
    }

}
extension ProposalDetailViewModel {
    
    func refresh() {
        viewItems.removeAll()
        getAbleVote()
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
    
    var catchVoted: Bool {
        if let id = votedIdCatch(), id == infoItem.info.id.description {
            return true
        }
        return false
    }
    
    var voteStateDesc: String {
        "safe_zone.safe4.vote.info.desc".localized("\(voteTotalNum)", "\(voteNum(state: .passed))", "\(voteNum(state: .abstain))", "\(voteNum(state: .refuse))")
    }
    
    var sendData: ProposalSendData {
        ProposalSendData(title: infoItem.info.title, desc: infoItem.info.description, amount: infoItem.info.payAmount.safe4ToDecimal() ?? 0, startPayTime: infoItem.info.startPayTime, endPayTime: infoItem.info.endPayTime, payTimes: Int(infoItem.info.payTimes))
    }
}

extension ProposalDetailViewModel {
    
    var stateDriver: Observable<ProposalDetailViewModel.State> {
        stateRelay.asObservable()
    }
    
    var isAbleVoteDriver: Driver<Bool> {
        isAbleVoteRelay.asDriver()
    }
}

extension ProposalDetailViewModel {
    
    enum State: Equatable {
        case loading
        case completed(datas: [ProposalDetailViewModel.ViewItem])
        case voteCompleted
        case failed(error: String)
        
        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
//            case let (.completed(lhsValue), .completed(rhsValue)): return lhsDatas == rhsValue
            case (.voteCompleted, .voteCompleted): return true
            case let (.failed(lhsValue), .failed(rhsValue)): return lhsValue == rhsValue
            default: return false
            }
        }
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
