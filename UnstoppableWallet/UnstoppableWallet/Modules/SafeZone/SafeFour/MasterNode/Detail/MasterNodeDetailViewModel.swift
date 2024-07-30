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
    private let nodeViewItem: MasterNodeViewModel.ViewItem
    private let service: MasterNodeDetailService
    
    private var stateRelay = PublishRelay<MasterNodeDetailViewModel.State>()
    private(set) var state: MasterNodeDetailViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private var isEnabledSend = true
    
    init(nodeViewItem: MasterNodeViewModel.ViewItem, service: MasterNodeDetailService) {
        self.service = service
        self.nodeViewItem = nodeViewItem
        viewItems = nodeViewItem.info.founders.map {ViewItem(info: $0)}
    }
}

extension MasterNodeDetailViewModel {
    
    func joinPartner(value: Float){
        Task { [service] in
            do{
                let value = BigUInt((Decimal(Double(value)) * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
                guard isEnabledSend else { return }
                isEnabledSend = false
                let _ = try await service.appendRegister(value: value, dstAddr: nodeViewItem.info.addr)
                isEnabledSend = true
                state = .partnerCompleted
            }catch{
                isEnabledSend = true
                state = .failed(error: "成为合伙人失败！")
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
        nodeViewItem.joinEnabled
    }
    
    var stateDriver: Observable<MasterNodeDetailViewModel.State> {
        stateRelay.asObservable()
    }
    
    var detailInfo: MasterNodeViewModel.ViewItem {
        nodeViewItem
    }
    
    struct ViewItem {
        let info: MasterNodeMemberInfo
        
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
}

extension MasterNodeDetailViewModel {
    enum State {
        case loading
        case partnerCompleted
        case failed(error: String)
    }
}
