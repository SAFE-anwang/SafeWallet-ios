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

class MasterNodeViewModel {
    private let servie: MasterNodeService
    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: false)
    private var stateRelay = PublishRelay<MasterNodeViewModel.State>()
    private var viewItems = [MasterNodeViewModel.ViewItem]()
    private var addressArray = [EthereumAddress]()

    private(set) var state: MasterNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(servie: MasterNodeService) {
        self.servie = servie
    }
}

extension MasterNodeViewModel {
    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task { [servie] in
            do{
                if !loadMore {
                   let totalNum = try await servie.getTotalNum()
                    safe4Page.set(totalNum: Int(totalNum))
                }
                guard safe4Page.totalNum > 0 else { return  state = .completed(datas: []) }
                guard addressArray.count < safe4Page.totalNum else { return }
                
                let addrs = try await servie.superNodeAddressArray(page: safe4Page)
                addressArray.append(contentsOf: addrs)
                
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask {
                            do {
                                let info = try await servie.getInfo(address: address)
                                let item = ViewItem(info: info)
                                return .success(item)
                            }catch{
                                return .failure(MasterNodeError.getInfo)
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
                results.sort{ Int($0.info.id) < Int($1.info.id) }
                if results.count > 0 { safe4Page.plusPage() }
                viewItems.append(contentsOf: results)
                state = .completed(datas: viewItems)
            }catch{
                state = .failed(error: "")
            }
        }
        
    }
    

}

extension MasterNodeViewModel {
    func refresh() {
        viewItems.removeAll()
        addressArray.removeAll()
        requestInfos(loadMore: false)
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        requestInfos(loadMore: true)
    }
}

extension MasterNodeViewModel {
    var nodeType: Safe4NodeType {
        servie.nodeType
    }
    
    var stateDriver: Observable<MasterNodeViewModel.State> {
        stateRelay.asObservable()
    }
}

extension MasterNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [MasterNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        let info: MasterNodeInfo
        
        var id: String {
            info.id.description
        }
        
        var amount: String {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return total.safe4FomattedAmount
        }
        
        var nodeState: MasterNodeState {
            switch info.state {
            case 0: return .initstate
            case 1: return .online
            case 2: return .abnormal
            default: return .unknown
            }
        }
        
        var foundersTotalAmount: Decimal {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return Decimal(bigUInt: total, decimals: safe4Decimals) ?? 0
        }
        
        var foundersBalanceAmount: Decimal {
            masterNodeRegisterSafeLockNum - foundersTotalAmount
        }
        
        var joinEnabled: Bool {
            let total = info.founders.map(\.amount) .reduce(0, +)
            return Decimal(bigUInt: total, decimals: safe4Decimals)! < masterNodeRegisterSafeLockNum
        }
        
    }
    
    enum MasterNodeError: Error {
        case getInfo
    }
    
    enum MasterNodeState {
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
