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

class MasterNodeChangeViewModel {
    let nodeInfo: MasterNodeViewModel.ViewItem
    private let service: MasterNodeChangeService
    private var stateRelay = PublishRelay<MasterNodeChangeViewModel.State>()
    private var viewItems = [MasterNodeViewModel.ViewItem]()
    
    private(set) var state: MasterNodeChangeViewModel.State = .unchanged(type: .address) {
        didSet {
            if state != oldValue {
                stateRelay.accept(state)
            }
        }
    }
    
    init(service: MasterNodeChangeService, viewItem: MasterNodeViewModel.ViewItem) {
        self.service = service
        self.nodeInfo = viewItem
        
        service.nodeAddress = viewItem.info.addr.address
        service.enode = viewItem.info.enode
        service.desc = viewItem.info.description
    }
    


}

extension MasterNodeChangeViewModel {
    
    func isChanged(type: MasterNodeInputType) -> Bool {
        switch type {
        case .address:
            service.nodeAddress != nodeInfo.info.addr.address
        case .ENODE:
            service.enode != nodeInfo.info.enode
        case .desc:
            service.desc != nodeInfo.info.description
        }
    }
    
    func onChange(text: String?, type: MasterNodeInputType) {
        switch type {
        case .address:
            service.nodeAddress = text
        case .ENODE:
            service.enode = text
        case .desc:
            service.desc = text
        }
        let isChanged = isChanged(type: type)
        if isChanged {
            state = .didchanged(type: type)
        }else {
            service.setCaution(type: type, caution: nil)
            state = .unchanged(type: type)
        }
    }

    func commitChange(type: MasterNodeInputType) {
        state = .loading
        Task {
            do{
                switch type {
                case .address:
                    let isValid = try await service.validateMasterNodeAddress()
                    guard let newAddress = service.nodeAddress, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeAddress(address: nodeInfo.info.addr, newAddress: newAddress)
                    state = .success
                    
                case .ENODE:
                    let isValid = try await service.validateMasterNodeEnode()
                    guard let enode = service.enode, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeEnode(address: nodeInfo.info.addr, enode: enode)
                    state = .success
                    
                case .desc:
                    let isValid = service.validateMasterNodeDesc()
                    guard let desc = service.desc, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeDescription(address: nodeInfo.info.addr, desc: desc)
                    state = .success
                    
                }
            }catch{
                if let nodeError = error as? Web3Core.Web3Error {
                    if case let .nodeError(error) = nodeError {
                        state = .faild(error: "")
                        var caution: Caution?
                        if error.contains("existent new address") {
                            caution = Caution(text: "safe_zone.safe4.update.address.error".localized, type: .error)
                        }
                        service.setCaution(type: type, caution: caution)
                    }
                }
            }
        }
    }
}

extension MasterNodeChangeViewModel {
    
    var stateDriver: Observable<MasterNodeChangeViewModel.State> {
        stateRelay.asObservable()
    }
    
    var addressCautionDriver: Driver<Caution?> {
        service.addressCautionDriver
    }
    var enodeCautionDriver: Driver<Caution?> {
        service.enodeCautionDriver
    }
    var descCautionDriver: Driver<Caution?> {
        service.descCautionDriver
    }
    
    enum State: Equatable {
        
        case unchanged(type: MasterNodeInputType)
        case didchanged(type: MasterNodeInputType)
        
        case loading
        case success
        case faild(error: String)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.unchanged(lhsValue), .unchanged(rhsValue)): return lhsValue == rhsValue
            case let (.didchanged(lhsValue), .didchanged(rhsValue)): return lhsValue == rhsValue
            default: return false
            }
        }
    }
    
    enum nodeError: String {
    case  existentAddress = "execution reverted: existent new address\nError code: 3" // 该地址已在主节点中注册,请使用其他地址.
    
    }
}
