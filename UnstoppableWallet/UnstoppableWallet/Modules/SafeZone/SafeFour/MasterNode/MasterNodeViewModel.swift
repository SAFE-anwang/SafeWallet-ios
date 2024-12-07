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
    private let service: MasterNodeService
    private var safe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: true)
    private var partnerSafe4Page = Safe4PageControl(initCount: 25, totalNum: 0, page: 0, isReverse: false)

    private var stateRelay = PublishRelay<MasterNodeViewModel.State>()
    private var viewItems = [MasterNodeViewModel.ViewItem]()
    private var partnerAddressArray = [EthereumAddress]()

    let type: MasterNodeModule.MasterNodeType

    private(set) var state: MasterNodeViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private let searchCautionRelay = BehaviorRelay<Caution?>(value:nil)

    init(service: MasterNodeService, type: MasterNodeModule.MasterNodeType) {
        self.service = service
        self.type = type
    }
}


// Mine
extension MasterNodeViewModel {
    
    private func requestMineNodeInfos(loadMore: Bool) {
        state = .loading
        Task { [self, service] in
            do {
                var partnerAddrs = [Web3Core.EthereumAddress]()
                if !loadMore {
                    let totalNum = try await service.getAddrNum4Creator()
                    safe4Page.set(totalNum: Int(totalNum))
                    partnerAddrs = try await allPartnerAddrs()
                }
                
                guard safe4Page.totalNum > 0 || partnerAddressArray.count > 0 else { return  state = .completed(datas: []) }
                guard viewItems.count < safe4Page.totalNum + partnerAddressArray.count else { return }
                
                var creatorAddrs = [Web3Core.EthereumAddress]()
                if safe4Page.totalNum > 0 {
                    creatorAddrs = try await service.getAddrs4Creator(page: safe4Page)
                }
                
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
                results.sort{ Int($0.info.id) > Int($1.info.id) }
                if results.count > 0 { safe4Page.plusPage() }
                viewItems.append(contentsOf: results)
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
                        return .failure(MasterNodeError.getInfo)
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
extension MasterNodeViewModel {
    private func requestInfos(loadMore: Bool) {
        state = .loading
        Task { [service] in
            do{
                if !loadMore {
                    let totalNum = try await service.getTotalNum()
                    safe4Page.set(totalNum: Int(totalNum))
                    let _ = try await allPartnerAddrs()
                }
                guard safe4Page.totalNum > 0 else { return  state = .completed(datas: []) }
                guard viewItems.count < safe4Page.totalNum else { return }
                
                let addrs = try await service.masteNodeAddressArray(page: safe4Page)
                
                var results: [ViewItem] = []
                var errors: [Error] = []
                await withTaskGroup(of: Result<ViewItem, Error>.self) { taskGroup in
                    for address in addrs {
                        taskGroup.addTask { [self] in
                            do {
                                let item = try await nodeInfoBy(address: address, isEnabledEdit: false)
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
                results.sort{ Int($0.info.id) > Int($1.info.id) }
                if results.count > 0 { safe4Page.plusPage() }
                viewItems.append(contentsOf: results)
                state = .completed(datas: viewItems)
            }catch{
                state = .failed(error: "")
            }
        }
        
    }
}

// search
extension MasterNodeViewModel {
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
                        let caution = Caution(text: "safe_zone.safe4.node.address.legal".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let address = Web3Core.EthereumAddress(text)!
                    let isExist = try await service.exist(address)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.node.address.notexist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(address: address, isEnabledEdit: false)
                    state = .searchResults(datas: [viewItem])
                    
                }else if let id = BigUInt(text) {
                    let isExist = try await service.existID(id)
                    guard isExist else {
                        let caution = Caution(text: "safe_zone.safe4.node.id.notexist".localized, type: .error)
                        searchCautionRelay.accept(caution)
                        state = .searchResults(datas: [])
                        return
                    }
                    let viewItem = try await nodeInfoBy(id: id)
                    state = .searchResults(datas: [viewItem])
                }else {
                    let caution = Caution(text: "safe_zone.safe4.node.id.address.input.tips".localized, type: .error)
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
        let info = try await service.getInfo(address: address)
        var ownerType: NodeOwnerType = .None
        if info.creator.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Creator
        }else if partnerAddressArray.contains(info.addr) {
            ownerType = .Partner
        }else if info.addr.address.lowercased() == service.address.address.lowercased() {
            ownerType = .Owner
        }
        return ViewItem(info: info, isNodeAddress: nodeType != .normal, isEnabledEdit: isEnabledEdit, ownerType: ownerType)
    }
}

extension MasterNodeViewModel {
    func refresh() {
        viewItems.removeAll()
        switch type {
        case .All:
            requestInfos(loadMore: false)
        case .Mine:
            requestMineNodeInfos(loadMore: false)
        }
    }
    
    func loadMore() {
        if case .loading = state {
           return
        }
        switch type {
        case .All:
            requestInfos(loadMore: true)
        case .Mine:
            requestMineNodeInfos(loadMore: true)
        }
    }
    
    func getLockId(viewItem: ViewItem) -> BigUInt? {
        return viewItem.info.founders
            .filter{$0.addr.address.lowercased() == service.address.address.lowercased()}.first?.lockID
    }
}

extension MasterNodeViewModel {
    var nodeType: Safe4NodeType {
        service.nodeType
    }
    
    var stateDriver: Observable<MasterNodeViewModel.State> {
        stateRelay.asObservable()
    }
    
    var searchCautionDriver: Driver<Caution?> {
        searchCautionRelay.asDriver()
    }
}

extension MasterNodeViewModel {
    
    enum State {
        case loading
        case completed(datas: [MasterNodeViewModel.ViewItem])
        case searchResults(datas: [MasterNodeViewModel.ViewItem])
        case failed(error: String)
    }
    
    struct ViewItem {
        let info: MasterNodeInfo
        let isNodeAddress: Bool
        let isEnabledEdit: Bool
        let ownerType: NodeOwnerType
        var joinAmount: BigUInt?
        
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
        
        var isEnabledJoin: Bool {
            hasBalance && !isNodeAddress
        }
        
        var hasBalance: Bool {
            let total = info.founders.map(\.amount) .reduce(0, +) + (joinAmount ?? 0)
            return Decimal(bigUInt: total, decimals: safe4Decimals)! < masterNodeRegisterSafeLockNum
        }
        
        var isEnabledAddLockDay: Bool {
            ownerType == .Creator || ownerType == .Partner
        }
        
        mutating func update(joinAmount: BigUInt?) {
            self.joinAmount = joinAmount
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
