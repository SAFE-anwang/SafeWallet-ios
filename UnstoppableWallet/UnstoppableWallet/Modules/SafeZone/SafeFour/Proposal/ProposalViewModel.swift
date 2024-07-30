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

class ProposalViewModel {
    private let servie: ProposalService
    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: true)
    private var stateRelay = PublishRelay<ProposalViewModel.State>()
    private var viewItems = [ProposalViewModel.ViewItem]()
    
    private(set) var state: ProposalViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(servie: ProposalService) {
        self.servie = servie
    }
}

extension ProposalViewModel {

    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task(priority: .userInitiated) { [servie] in
            do{
                if !loadMore {
                   let totalNum = try await servie.getTotalNum()
                    safe4Page.set(totalNum: totalNum)
                }
                guard safe4Page.totalNum > 0 else { return  state = .completed(datas: []) }
                guard viewItems.count < safe4Page.totalNum else { return }
                
                let ids = try await servie.proposalIds(page: safe4Page)
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for id in ids {
                        taskGroup.addTask {
                            do {
                                let info = try await servie.getInfo(id: id)
                                let item = ViewItem(info: info)
                                return .success(item)
                            }catch{
                                return .failure(ProposalError.getInfo)
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
                results.sort{ Int($0.info.id) > Int($1.info.id) }
                if results.count > 0 { safe4Page.plusPage() }
                viewItems.append(contentsOf: results)
                state = .completed(datas: viewItems)
            }catch{
                state = .failed(error: error.localizedDescription)
            }
        }
    }
}

extension ProposalViewModel {
    
    func refresh() {
        viewItems.removeAll()
        requestInfos(loadMore: false)
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        requestInfos(loadMore: true)
    }
}

extension ProposalViewModel {
    var stateDriver: Observable<ProposalViewModel.State> {
        stateRelay.asObservable()
    }
}

extension ProposalViewModel {
    
    enum State {
        case loading
        case completed(datas: [ProposalViewModel.ViewItem])
        case failed(error: String)
    }
        
    struct ViewItem {
        let info: ProposalInfo
        
        var id: String {
            info.id.description
        }
        
        var amount: String {
            info.payAmount.safe4FomattedAmount
        }
        
        var status: ProposalState {
            if Double(info.startPayTime) > Date.now.timeIntervalSince1970 {
                return .voting
            }
            return  info.state == 0 ? .invalid : .passed
        }
        
        var dateText: String {
            let date = Date(timeIntervalSince1970: Double(info.startPayTime))
            return DateHelper().safe4Format(date: date)
        }
        
        var distribution: String {
            if info.payTimes < 2 {
                return "在 \(dateText)\n一次性发放 \(amount) SAFE"
            }
            let date = Date(timeIntervalSince1970: Double(info.endPayTime))
            let end = DateHelper().safe4Format(date: date)
            return "在\(dateText)到\(end)\n分期\(info.payTimes)次 合计发放 \(amount) SAFE"
        }
        
//        var ableVote: Bool {
//            
//        }
    }
    
    enum ProposalState {
        case voting
        case passed
        case invalid
        
        var title: String {
            switch self {
            case .voting:
                return "safe_zone.safe4.state.voting".localized
            case .passed:
                return "safe_zone.safe4.state.passed".localized
            case .invalid:
                return "safe_zone.safe4.state.invalid".localized
            }
        }
        
        var color: UIColor {
            switch self {
            case .voting:
                return .themeIssykBlue
            case .passed:
                return  .themeRemus
            case .invalid:
                return  .themeElena
            }
        }
    }
    
    enum ProposalError: Error {
        case getInfo
    }

}
