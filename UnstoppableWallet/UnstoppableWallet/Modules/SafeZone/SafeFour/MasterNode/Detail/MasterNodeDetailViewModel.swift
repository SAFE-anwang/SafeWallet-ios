import Foundation
import UIKit
import HsToolKit
import BigInt
import web3swift
import Web3Core
import HsExtensions
import ThemeKit
import RxSwift
import RxRelay
import RxCocoa

class MasterNodeDetailViewModel {
    private(set) var viewItems = [MasterNodeDetailViewModel.ViewItem]()
    private(set) var nodeType: Safe4NodeType
    private var nodeViewItem: MasterNodeViewModel.ViewItem
    private let service: MasterNodeDetailService
    
    private var stateRelay = PublishRelay<MasterNodeDetailViewModel.State>()
    private(set) var state: MasterNodeDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private var isEnabledSend = true
    
    init(nodeType: Safe4NodeType, nodeViewItem: MasterNodeViewModel.ViewItem, service: MasterNodeDetailService) {
        self.nodeType = nodeType
        self.service = service
        self.nodeViewItem = nodeViewItem
        viewItems = nodeViewItem.info.founders.map {ViewItem(info: $0, isSelf: service.address.lowercased() == $0.addr.address.lowercased())}
    }
}

extension MasterNodeDetailViewModel {
    
    var minimumSafeValue: Float {
        100
    }
    
    var lockDay: BigUInt {
        720
    }
    
    func joinPartner(value: Float){
        Task { [service] in
            do{
                let value = BigUInt((Decimal(Double(value)) * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
                guard isEnabledSend else { return }
                isEnabledSend = false
                let _ = try await service.appendRegister(value: value, dstAddr: nodeViewItem.info.addr, lockDay: lockDay)
                isEnabledSend = true
                update(joinAmount: value)
                state = .partnerCompleted
            }catch{
                isEnabledSend = true
                state = .failed(error: "safe_zone.safe4.partner.join.failed".localized)
            }
        }
    }
}

extension MasterNodeDetailViewModel {
    
    var balance: String {
        "\(service.balance ?? 0.00) SAFE"
    }
    
    var balanceDriver: Driver<Decimal?> {
        service.balanceDriver
    }
    
    var joinEnabled: Bool {
        nodeViewItem.isEnabledJoin
    }
    
    var stateDriver: Observable<MasterNodeDetailViewModel.State> {
        stateRelay.asObservable()
    }
    
    var detailInfo: MasterNodeViewModel.ViewItem {
        nodeViewItem
    }
    
    struct ViewItem {
        let info: MasterNodeMemberInfo
        let isSelf: Bool
        
        var id: String {
            info.lockID.description
        }
        
        var address: String {
            info.addr.address
        }
        
        var safeAmount: String {
            return info.amount.safe4FomattedAmount + " SAFE"
        }
    }
    
    var sendData: MasterNodeSendData {
        MasterNodeSendData(address: nodeViewItem.info.addr.address, ENODE: nodeViewItem.info.enode, desc: nodeViewItem.info.description, amount: 0)
    }
    
    func update(joinAmount: BigUInt?) {
        nodeViewItem.update(joinAmount: joinAmount)
    }
}

extension MasterNodeDetailViewModel {
    enum State {
        case loading
        case partnerCompleted
        case failed(error: String)
    }
    
    
    enum ViewType {
        case Detail
        case JoinPartner
    }
}
