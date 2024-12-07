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

class SuperNodeChangeViewModel {
    let nodeInfo: SuperNodeViewModel.ViewItem
    private let service: SuperNodeChangeService
    private var stateRelay = PublishRelay<SuperNodeChangeViewModel.State>()
    private var viewItems = [SuperNodeViewModel.ViewItem]()
    
    private(set) var state: SuperNodeChangeViewModel.State = .unchanged(type: .name) {
        didSet {
            if state != oldValue {
                stateRelay.accept(state)
            }
        }
    }
    
    init(service: SuperNodeChangeService, viewItem: SuperNodeViewModel.ViewItem) {
        self.service = service
        self.nodeInfo = viewItem
        
        service.name = viewItem.info.name
        service.nodeAddress = viewItem.info.addr.address
        service.enode = viewItem.info.enode
        service.desc = viewItem.info.description
    }
    


}

extension SuperNodeChangeViewModel {
    
    func isChanged(type: SuperNodeInputType) -> Bool {
        switch type {
        case .address:
            service.nodeAddress != nodeInfo.info.addr.address
        case .ENODE:
            service.enode != nodeInfo.info.enode
        case .desc:
            service.desc != nodeInfo.info.description
        case .name:
            service.name != nodeInfo.info.name
        }
    }
    
    func onChange(text: String?, type: SuperNodeInputType) {
        switch type {
        case .address:
            service.nodeAddress = text
        case .ENODE:
            service.enode = text
        case .desc:
            service.desc = text
        case .name:
            service.name = text
        }
        let isChanged = isChanged(type: type)
        if isChanged {
            state = .didchanged(type: type)
        }else {
            service.setCaution(type: type, caution: nil)
            state = .unchanged(type: type)
        }
    }

    func commitChange(type: SuperNodeInputType) {
        state = .loading
        Task {
            do{
                switch type {
                case .name:
                    let isValid = try await service.validateSuperNodeName()
                    guard let name = service.name, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeName(address: nodeInfo.info.addr, name: name)
                    state = .success
                    
                case .address:
                    let isValid = try await service.validateSuperNodeAddress(current: nodeInfo.info.addr.address)
                    guard let newAddress = service.nodeAddress, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeAddress(address: nodeInfo.info.addr, newAddress: newAddress)
                    state = .success
                    
                case .ENODE:
                    let isValid = try await service.validateSuperNodeEnode()
                    guard let enode = service.enode, isValid else { return state = .faild(error: "") }
                    let _ = try await service.changeEnode(address: nodeInfo.info.addr, enode: enode)
                    state = .success
                    
                case .desc:
                    let isValid = service.validateSuperNodeDesc()
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
                            caution = Caution(text: "safe_zone.safe4.node.super.address.used.tips".localized, type: .error)
                        }else if error.contains("existent name") {
                            caution = Caution(text: "safe_zone.safe4.node.super.name.used.tips".localized, type: .error)
                        }else {
                            caution = Caution(text: error, type: .error)
                        }
                        service.setCaution(type: type, caution: caution)
                    }
                }
            }
        }
    }
}

extension SuperNodeChangeViewModel {
    
    var stateDriver: Observable<SuperNodeChangeViewModel.State> {
        stateRelay.asObservable()
    }
    
    var addressCautionDriver: Driver<Caution?> {
        service.addressCautionDriver
    }
    var nameCautionDriver: Driver<Caution?> {
        service.nameCautionDriver
    }
    var enodeCautionDriver: Driver<Caution?> {
        service.enodeCautionDriver
    }
    var descCautionDriver: Driver<Caution?> {
        service.descCautionDriver
    }
    
    enum State: Equatable {
        
        case unchanged(type: SuperNodeInputType)
        case didchanged(type: SuperNodeInputType)
        
        case loading
        case success
        case faild(error: String)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.unchanged(lhsValue), .unchanged(rhsValue)): return lhsValue == rhsValue
            case let (.didchanged(lhsValue), .didchanged(rhsValue)): return lhsValue == rhsValue
            case (.loading, .loading): return true
            case (.success, .success): return true

            default: return false
            }
        }
    }
}
