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

class ProposalViewModel {
    let service: ProposalService
    private var safe4Page = Safe4PageControl(pageSize: 20, isReverse: true)
    private var stateRelay = PublishRelay<ProposalViewModel.State>()
    private var viewItems = [ProposalViewModel.ViewItem]()
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)
    let proposalStorageManager: ProposalStorageManager
    @Published var hasNewProposal: Bool = false

    private(set) var state: ProposalViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(service: ProposalService) {
        self.service = service
        self.proposalStorageManager = ProposalStorageManager()
    }
}

extension ProposalViewModel {

    private func requestInfos(loadMore: Bool, completed: (()-> Void)?) {
        state = .loading
        Task(priority: .userInitiated) { [service] in
            do{
                if !loadMore {
                   let totalNum = try await service.getTotalNum()
                    safe4Page.set(totalNum: totalNum)
                }
                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }
                
                let ids = try await service.proposalIds(page: safe4Page)
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for id in ids {
                        taskGroup.addTask {
                            do {
                                let info = try await service.getInfo(id: id)
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
                self.proposalStorageManager.save(infos: results.map{ ProposalInfoRecord(info: $0.info)})
                self.proposalStorageManager.savePageControl(safe4Page)
                viewItems.append(contentsOf: results)
                state = .completed(datas: viewItems)
                completed?()
            }catch{
                state = .failed(error: error.localizedDescription)
            }
        }
    }
    
    func loadCache() {
        guard let pageControl = proposalStorageManager.getPageControl() else { return }
        var caches = proposalStorageManager.loadCaches().map{ViewItem(info: $0.transform())}
        caches.sort{ Int($0.info.id) > Int($1.info.id) }
        viewItems = caches
        safe4Page = pageControl
        state = .completed(datas: viewItems)
    }
    
    func clearCaches() {
        proposalStorageManager.clearCaches()
    }
}
// load new Proposal
extension ProposalViewModel {
    func loadNewProposals() {
        self.hasNewProposal = ProposalStorageManager.getNeedShowTips()
        if case .All = service.type {
            Task {
                let totalNum = try await service.getTotalNum()
                if let pageControl = proposalStorageManager.getPageControl(), pageControl.totalNum < Int(totalNum) {
                    safe4Page.set(totalNum: totalNum)
                    requestInfos(loadMore: false) {
                        self.hasNewProposal = true
                        self.proposalStorageManager.savePageControl(self.safe4Page)
                        ProposalStorageManager.saveNeedShowTips(self.hasNewProposal)
                    }
                }else {
                    requestInfos(loadMore: true) {
                        self.hasNewProposal = self.viewItems.count > 0
                        ProposalStorageManager.saveNeedShowTips(self.hasNewProposal)
                    }
                }
            }
        }
    }
}
// search
extension ProposalViewModel {
    func search(text: String?) {
        searchCautionRelay.accept(nil)
        guard let text, text.count > 0 else {
            state = .completed(datas: viewItems)
            return
        }
        state = .loading
        Task {
            do {
                if let id = BigUInt(text) {
                    let isExist = try await service.exist(id)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.proposal.create.ID.exist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await proposalInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "safe_zone.safe4.proposal.create.ID.input.tips".localized, type: .error)
                    searchCautionRelay.accept(caution)
                    state = .searchResults(datas: [])
                }
            }catch{
                state = .searchResults(datas: [])
            }
        }
    }
    
    private func proposalInfoBy(id: BigUInt) async throws -> ViewItem {
        let info = try await service.getInfo(id: id)
        return ViewItem(info: info)
    }
}

extension ProposalViewModel {
    
    func refresh() {
        viewItems.removeAll()
        if case .All = service.type {
            if let pageControl = proposalStorageManager.getPageControl(), proposalStorageManager.totalCacheNum > 0 {
                safe4Page.set(totalNum: pageControl.totalNum)
                loadCache()
            }else {
                requestInfos(loadMore: false, completed: nil)
            }
        }else {
            requestInfos(loadMore: false, completed: nil)
        }

    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        if safe4Page.isAbleLoadMore {
            requestInfos(loadMore: true, completed: nil)
        }
    }
}

extension ProposalViewModel {
    
    var type: ProposalModule.ProposalType {
        service.type
    }
    
    var stateDriver: Observable<ProposalViewModel.State> {
        stateRelay.asObservable()
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension ProposalViewModel {
    
    enum State {
        case loading
        case completed(datas: [ProposalViewModel.ViewItem])
        case searchResults(datas: [ProposalViewModel.ViewItem])
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
        
        var payDateText: String {
            let date = Date(timeIntervalSince1970: Double(info.startPayTime))
            let start = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? Date()// next day
            return DateHelper().safe4Format(date: start)
        }

        var distribution: String {
            if info.payTimes < 2 {
                return "safe_zone.safe4.pay.method.disposabl.desc".localized("\(payDateText)", "\(amount)")
            }
            let date = Date(timeIntervalSince1970: Double(info.endPayTime))
            let end = info.startPayTime == info.startPayTime ? payDateText : DateHelper().safe4Format(date: date)
            return "safe_zone.safe4.pay.method.instalment.desc".localized("\(payDateText)", "\(end)", "\(info.payTimes)", "\(amount)")
        }

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
