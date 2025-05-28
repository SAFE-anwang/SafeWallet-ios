import Combine
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt

class WithdrawViewModel: ObservableObject {
    private let nullAddress = "0x0000000000000000000000000000000000000000"
    private let service: WithdrawViewService
    
    @Published private(set) var dataState: DataStatus<[WithdrawItem]> = .loading
    @Published private(set) var sendState: SendStatus = .normal
    
    @Published var selectedItems: [WithdrawItem] = [] {
        didSet {
            withdrawEnabled = selectedItems.count > 0
        }
    }
    @Published var withdrawEnabled = false
    
    var onSuccess: ((SendStatus) -> Void)?
    
    private var items: [WithdrawItem] = []
    
    init(service: WithdrawViewService) {
        self.service = service
        withdrawItems()
    }
}

extension WithdrawViewModel {
    func choose(item: WithdrawItem) {
        if let index = selectedItems.firstIndex(where: { $0.id == item.id }) {
            selectedItems.remove(at: index)
        }else {
            selectedItems.append(item)
        }
    }
    
    func isSelected(item: WithdrawItem) -> Bool {
        if let _ = selectedItems.firstIndex(where: { $0.id == item.id }) {
            return true
        }else {
            return false
        }
    }
    
    func withdraw() {
        sendState = .loading
        withdrawEnabled = false
        let ids = selectedItems.map { $0.id }
        Task {
            do{
                let _ = try await service.withdrawByID(ids: ids)
                sendState = .completed
                withdrawEnabled = true
                onSuccess?(sendState)
            }catch{
                withdrawEnabled = true
                sendState = .failed(RequestError.withdrawError)
                onSuccess?(sendState)
            }
        }
    }
    
    func chooseAll() {
        selectedItems = enableItems
        
    }
    
    func cancelAll() {
        selectedItems.removeAll()
    }
    
    var enableItems: [WithdrawItem] {
        items.filter{$0.isEnable == true}
    }
    
    var isChoosedAll: Bool {
        return (enableItems.count > 0) && selectedItems == enableItems
    }
    
    var title: String {
        service.type.title
    }
    
    var withdrawType: SafeWithdrawType {
        service.type
    }
}

extension WithdrawViewModel {
    
    func withdrawItems() {
        dataState = .loading
        Task {
            do{
                let ids = try await requestIDs().filter{$0 != 0}
                let infos = try await getRecordInfos(ids: ids)
                
                var results: [(web3swift.AccountRecord, RecordUseInfo)] = []
                
                switch service.type {
                case .masterNode:
                    let tempArray = infos.filter{$0.1.frozenAddr.address != nullAddress}
                    let array = await node(nodeType: .masterNode, records: tempArray)
                    results = array
                    
                case .superNode:
                    let tempArray = infos.filter{$0.1.frozenAddr.address != nullAddress}
                    let array = await node(nodeType: .superNode, records: tempArray)
                    results = array
                    
                case .proposal:
                    let proposalArray = infos.filter{$0.1.votedAddr.address == nullAddress && $0.1.frozenAddr.address == nullAddress}
                    results = proposalArray
                    
                case .voteLocked:
                    let voteArray = infos.filter{$0.1.votedAddr.address != nullAddress}
                    results = voteArray
                }
                
                let datas = results.map { WithdrawItem(id: $0.0.id,
                                                       amount: $0.0.amount.safe4FomattedAmount + " SAFE",
                                                       unlockHeight: $0.0.unlockHeight,
                                                       releaseHeight: $0.1.releaseHeight,
                                                       address: $0.1.votedAddr.address,
                                                       isEnable: ($0.0.unlockHeight.isZero ? $0.1.releaseHeight : $0.0.unlockHeight) < (service.lastBlockHeight ?? 0)
                                                       )
                    }
                items = datas
                DispatchQueue.main.async { [self] in
                    dataState = .completed(datas)
                }
            }catch{
                
            }
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
        return results
    }
    
    private func requestIDs() async throws -> [BigUInt] {

        let pageControl = try await pageControl()
        
        guard pageControl.totalNum > 0 else { return [] }
        
        var results: [BigUInt] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<[BigUInt], Error>.self) { taskGroup in
            for page in pageControl.pageArray {
                taskGroup.addTask { [self] in
                    do {
                        guard let start = page.first else{ return .failure(RequestError.pageError) }
                        let ids = try await ids(start: start, count: page.count)
                        return .success(ids)

                    }catch{
                        return .failure(RequestError.getInfo)
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
        return results
    }
        
    private func pageControl() async throws -> Safe4PageControl {
        var pageControl = Safe4PageControl(initCount: 50, totalNum: 0, page: 0, isReverse: false)
        let totalNum: BigUInt
        
        switch service.type {
        case .masterNode, .superNode, .proposal:
            totalNum = try await service.totalNum()
            
        case .voteLocked:
            totalNum = try await service.getVotedIDNum4Voter()
        }
        
        pageControl.set(totalNum: Int(totalNum))
        return pageControl
    }
    
    private func ids(start: Int, count: Int) async throws -> [BigUInt] {
        let ids: [BigUInt]
        switch service.type {
        case .masterNode, .superNode, .proposal:
            ids = try await service.getAvailableIDs(start: BigUInt(start), count: BigUInt(count))
            
        case .voteLocked:
            ids = try await service.getVotedIDs4Voter(start: BigUInt(start), count: BigUInt(count))
        }
        return ids
    }
    
    private func node(nodeType: WithdrawViewService.NodeType, records: [(web3swift.AccountRecord, RecordUseInfo)]) async -> [(web3swift.AccountRecord, RecordUseInfo)] {
        var results: [(web3swift.AccountRecord, RecordUseInfo)] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<(web3swift.AccountRecord, RecordUseInfo), Error>.self) { taskGroup in
            for node in records {
                taskGroup.addTask { [self] in
                    do {
                        switch nodeType {
                        case .masterNode:
                            let isMaster = try await service.isMasterNodeFounder(node.1.frozenAddr)
                            return isMaster ? .success(node) : .failure(RequestError.getInfo)
                
                        case .superNode:
                            let isSuper = try await service.isSuperNodeFounder(node.1.frozenAddr)
                            return isSuper ? .success(node) : .failure(RequestError.getInfo)
                        }
                        
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
        return results
    }
}

extension WithdrawViewModel {
    enum RequestError: Error {
        case pageError
        case getInfo
        case withdrawError
    }
    
    enum SendStatus {
        case normal
        case loading
        case failed(Error)
        case completed
    }
}

struct WithdrawItem: Equatable {
    let id: BigUInt
    let amount: String
    let unlockHeight: BigUInt
    let releaseHeight: BigUInt
    let address: String
    let isEnable: Bool
    
    var idStr: String {
        id.description
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
