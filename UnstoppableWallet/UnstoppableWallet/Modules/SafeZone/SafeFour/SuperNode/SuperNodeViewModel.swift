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

class SuperNodeViewModel {
    private let servie: SuperNodeService
    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: false)
    private var stateRelay = PublishRelay<SuperNodeViewModel.State>()
    private var viewItems = [SuperNodeViewModel.ViewItem]()

    private(set) var state: SuperNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(servie: SuperNodeService) {
        self.servie = servie
    }
}

extension SuperNodeViewModel {
    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task { [servie] in
            do{
                if !loadMore {
                   let totalNum = try await servie.getTotalNum()
                    safe4Page.set(totalNum: Int(totalNum))
                }
                let allVoteNum = try await servie.getAllVoteNum()
                guard safe4Page.totalNum > 0 else { return  state = .completed(datas: []) }
                guard viewItems.count < safe4Page.totalNum else { return }
                let addrs = try await servie.superNodeAddressArray(page: safe4Page)
                if addrs.count > 0 { safe4Page.plusPage() }
                
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask {
                            do {
                                async let info = try servie.getInfo(address: address)
                                async let totalVoteNum = try servie.getTotalVoteNum(address: address)
                                async let totalAmount = try servie.getTotalAmount(address: address)
                                let item = try await ViewItem(info: info, totalVoteNum: totalVoteNum, totalAmount: totalAmount, allVoteNum: allVoteNum)
                                return .success(item)
                            }catch{
                                return .failure(SuperNodeError.getInfo)
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
                var sortedResults = [ViewItem]()
                for address in addrs {
                    for  result in results {
                        if result.info.addr.address == address.address {
                            sortedResults.append(result)
                        }
                    }
                }
                viewItems.append(contentsOf: sortedResults)
                state = .completed(datas: viewItems)
            }catch{
                state = .failed(error: "")
            }
        }
    }
}

extension SuperNodeViewModel {
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

extension SuperNodeViewModel {
    
    var stateDriver: Observable<SuperNodeViewModel.State> {
        stateRelay.asObservable()
    }
    
    var nodeType: Safe4NodeType {
        servie.nodeType
    }
}

extension SuperNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [SuperNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        let info: SuperNodeInfo
        let totalVoteNum: BigUInt
        let totalAmount: BigUInt
        let allVoteNum: BigUInt
        
        let pledgeNum: BigUInt = 5000
                
        var desc: String {
            info.description
        }
        var id: String {
            info.id.description
        }
        var nodeState: SuperNodeState {
            switch info.state {
            case 0: return .initstate
            case 1: return .online
            case 2: return .abnormal
            default: return .unknown
            }
        }
        
        var rate: Decimal {
            let voteNum = Decimal(bigUInt: totalVoteNum, decimals: safe4Decimals) ?? 0
            guard let allVoteNum = Decimal(bigUInt: allVoteNum, decimals: safe4Decimals) else { return 0 }
            return (voteNum / allVoteNum)
        }
        
        var foundersTotalAmount: Decimal {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return Decimal(bigUInt: total, decimals: safe4Decimals) ?? 0
        }
        
        var foundersBalanceAmount: Decimal {
            superNodeRegisterSafeLockNum - foundersTotalAmount
        }
        
        var joinEnabled: Bool {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return foundersTotalAmount < superNodeRegisterSafeLockNum
        }
    }
    
    enum SuperNodeError: Error {
        case getInfo
    }
    
    enum SuperNodeState {
        case initstate
        case online
        case abnormal
        case unknown
        var title: String {
            switch self {
            case .initstate:
                "safe_zone.safe4.state.init".localized
            case .online:
                "safe_zone.safe4.state.online".localized
            case .abnormal:
                "safe_zone.safe4.state.abnormal".localized
            case .unknown:
                "safe_zone.safe4.state.unknown".localized
            }
        }
        
        var color: UIColor {
            switch self {
            case .initstate:
                    .themeRemus
            case .online:
                    .themeIssykBlue
            case .abnormal:
                    .themeElena
            case .unknown:
                    .themeElena
            }
        }
    }
}

