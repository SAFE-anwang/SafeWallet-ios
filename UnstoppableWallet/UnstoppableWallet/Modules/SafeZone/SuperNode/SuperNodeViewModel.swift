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

class SuperNodeViewModel: ObservableObject {
    let type: SuperNodeModule.SuperNodeType
    private let service: SuperNodeService
    private let disposeBag = DisposeBag()
    private var safe4Page = Safe4PageControl(pageSize: 10)
    private var partnerSafe4Page = Safe4PageControl(pageSize: 10)
    private var partnerAddressArray = [EthereumAddress]()
    private var nodeStorageManager: NodeStorageManager

    private var stateRelay = PublishRelay<SuperNodeViewModel.State>()
    private var viewItems = [SuperNodeViewModel.ViewItem]()
    private var cacheItems = [SuperNodeViewModel.ViewItem]()

    private(set) var state: SuperNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    var address: String {
        service.receiveAddress
    }
    
    init(service: SuperNodeService, type: SuperNodeModule.SuperNodeType) {
        self.service = service
        self.type = type
        self.nodeStorageManager = NodeStorageManager(nodeType: .superNode, pageControl: safe4Page)

        subscribe(disposeBag, service.syncRefreshObservable) { [weak self] _ in self?.refresh() }
        
//        if let (pageControl, caches) = nodeStorageManager.load() {
//            let cacheItems = caches.map { ViewItem(info: $0.transformToSuper(),
//                                                   totalVoteNum: 0,
//                                                   totalAmount: 0,
//                                                   allVoteNum: 0,
//                                                   ownerType: ownerType(info: $0.transformToSuper()),
//                                                   nodeType: nodeType,
//                                                   isEnabledEdit: false)
//                  }
//            self.cacheItems = cacheItems
//            self.viewItems.append(contentsOf: cacheItems)
//            self.safe4Page = pageControl
//        }
    }
}

// Mine
extension SuperNodeViewModel {
    
    private func requestMineNodeInfos(loadMore: Bool) {
        state = .loading
        Task { [service] in
            do {
                var partnerAddrs = [Web3Core.EthereumAddress]()
                if !loadMore {
                   let totalNum = try await service.getAddrNum4Creator()
                    safe4Page.set(totalNum: Int(totalNum))
                    partnerAddrs = try await allPartnerAddrs()
                }
                guard safe4Page.totalNum > 0 || partnerAddressArray.count > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard viewItems.count < safe4Page.totalNum + partnerAddressArray.count else {
                    state = .completed(datas: viewItems)
                    return
                }
                var creatorAddrs = [Web3Core.EthereumAddress]()
                if safe4Page.totalNum > 0 {
                    creatorAddrs = try await service.getAddrs4Creator(page: safe4Page)
                }
                if creatorAddrs.count > 0 { safe4Page.plusPage() }
                let addrs = partnerAddrs + creatorAddrs

                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask { [self] in
                            do {
                                let item = try await nodeInfoBy(address: address, isEnabledEdit: true)
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
    
    private func allPartnerAddrs() async throws -> [Web3Core.EthereumAddress] {
        let totalNum = try await service.getAddrNum4Partner(addr: service.address.address)
        partnerSafe4Page.set(totalNum: Int(totalNum))
        guard partnerSafe4Page.totalNum > 0 else { return [] }
        
        var results: [Web3Core.EthereumAddress] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<[Web3Core.EthereumAddress], Error>.self) { taskGroup in
            for page in partnerSafe4Page.pageArray {
                taskGroup.addTask { [self] in
                    do {
                        let partnerAddrs = try await service.getAddrs4Partner(addr: service.address.address, start: BigUInt(page.first ?? 0), count: BigUInt(page.count))
                        return .success(partnerAddrs)
                    }catch{
                        return .failure(SuperNodeError.getInfo)
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
        partnerAddressArray = results
        return results
    }
}

// All
extension SuperNodeViewModel {
    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task { [service] in
            do{
                if !loadMore {
                   let totalNum = try await service.getTotalNum()
                    safe4Page.set(totalNum: Int(totalNum))
                    let _ = try await allPartnerAddrs()
                }
                guard safe4Page.totalNum > 0 else {
                    state = .completed(datas: [])
                    return
                }
                guard viewItems.count < safe4Page.totalNum else {
                    state = .completed(datas: viewItems)
                    return
                }
                let addrs = try await service.superNodeAddressArray(page: safe4Page)
                if addrs.count > 0 { safe4Page.plusPage() }
                
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask { [self] in
                            do {
                                let item = try await nodeInfoBy(address: address, isEnabledEdit: false)
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

// search
extension SuperNodeViewModel {
    func search(text: String?) {
        searchCautionRelay.accept(nil)
        guard let text, text.count > 0 else {
            state = .completed(datas: viewItems)
            return
        }
        state = .loading
        Task {
            do {
                if text.contains("0x") {
                    guard service.isValidAddress(text) else {
                        let caution = Caution(text: "请输入合法的节点地址".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let address = Web3Core.EthereumAddress(text)!
                    let isExist = try await service.exist(address)
                    guard isExist else {
                        let caution = Caution(text: "节点地址不存在".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(address: address, isEnabledEdit: false)
                    state = .searchResults(datas: [viewItem])
                    
                }else if let id = BigUInt(text) {
                    let isExist = try await service.existID(id)
                    guard isExist else {
                        let caution = Caution(text: "节点ID不存在".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "请输入合法的节点ID或地址".localized, type: .error)
                    searchCautionRelay.accept(caution)
                    state = .searchResults(datas: [])
                }
            }catch{
                state = .searchResults(datas: [])
            }
        }
    }
    
    private func nodeInfoBy(id: BigUInt) async throws -> ViewItem {
        let info = try await service.getInfoByID(id)
        return try await nodeInfoBy(address: info.addr, isEnabledEdit: false)
    }
    
    private func nodeInfoBy(address: Web3Core.EthereumAddress, isEnabledEdit: Bool) async throws -> ViewItem {
        async let allVoteNum = try service.getAllVoteNum()
        async let totalVoteNum = try service.getTotalVoteNum(address: address)
        async let totalAmount = try service.getTotalAmount(address: address)
        let info = try await service.getInfo(address: address)

        var ownerType: NodeOwnerType = .None
        
        if info.addr.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Owner
        }
        
        if info.creator.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Creator
        }
        
        if partnerAddressArray.contains(info.addr) {
            ownerType = .Partner
        }
        return try await ViewItem(info: info, totalVoteNum: totalVoteNum, totalAmount: totalAmount, allVoteNum: allVoteNum, ownerType: ownerType, nodeType: nodeType, isEnabledEdit: isEnabledEdit)
    }
}

extension SuperNodeViewModel {
    func refresh() {
        viewItems.removeAll()
        switch type {
        case .All:
            requestInfos(loadMore: false)
        case .Mine:
            requestMineNodeInfos(loadMore: false)
        }
    }
    
    func clearCaches() {
        if case .All = type {
            safe4Page.reset()
            nodeStorageManager.clearCaches()
            cacheItems.removeAll()
            viewItems.removeAll()
        }
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        switch type {
        case .All:
            if safe4Page.isAbleLoadMore {
                requestInfos(loadMore: true)
            }
        case .Mine:
            requestMineNodeInfos(loadMore: true)
        }
    }
    
    func getLockId(viewItem: ViewItem) -> BigUInt? {
        return viewItem.info.founders
            .filter{$0.addr.address.lowercased() == service.address.address.lowercased()}.first?.lockID
    }
}

extension SuperNodeViewModel {
    
    var stateDriver: Observable<SuperNodeViewModel.State> {
        stateRelay.asObservable()
    }
    
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension SuperNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [SuperNodeViewModel.ViewItem])
        case searchResults(datas: [SuperNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        
        let info: SuperNodeInfo
        let totalVoteNum: BigUInt
        let totalAmount: BigUInt
        let allVoteNum: BigUInt

        let ownerType: NodeOwnerType
        let nodeType: Safe4NodeType
        let isEnabledEdit: Bool

        var joinAmount: BigUInt?

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
            let total = info.founders.map(\.amount) .reduce(0, +) + (joinAmount ?? 0)
            return Decimal(bigUInt: total, decimals: safe4Decimals) ?? 0
        }
        
        var foundersBalanceAmount: Decimal {
            superNodeRegisterSafeLockNum - foundersTotalAmount
        }
        
        var hasBalance: Bool {
            return foundersTotalAmount < superNodeRegisterSafeLockNum
        }
        
        var isNodeAddress: Bool {
            nodeType != .normal
        }
        
        var isEnabledJoin: Bool {
            hasBalance && !isNodeAddress
        }
        
        var isEnabledVote: Bool {
            nodeType != .superNode && !hasBalance
        }
        
        var isEnabledAddLockDay: Bool {
            ownerType == .Creator || ownerType == .Partner
        }
        
        mutating func update(joinAmount: BigUInt?) {
            self.joinAmount = joinAmount
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
    
    enum NodeOwnerType {
        case Owner
        case Creator
        case Partner
        case None
        
        var title: String {
            switch self {
            case .Owner: ""
            case .Creator: "safe_zone.safe4.node.creator".localized
            case .Partner: "safe_zone.safe4.partner".localized
            case .None: ""
            }
        }
    }
}
