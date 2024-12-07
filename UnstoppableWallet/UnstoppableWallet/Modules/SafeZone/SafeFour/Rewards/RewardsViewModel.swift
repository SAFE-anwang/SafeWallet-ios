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

class RewardsViewModel {
    private let service: RewardsService
    private let disposeBag = DisposeBag()
    private var viewItems = [Safe4Reward]()
    
    private let viewItemsRelay = BehaviorRelay<[ViewItem]?>(value: nil)

    init(service: RewardsService) {
        self.service = service
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
    }

    private func sync(state: RewardsService.State) {
        switch state {
        case .loading:
            viewItemsRelay.accept(nil)
            
        case let .completed(datas):
            viewItemsRelay.accept(datas)

        case .failed:
            viewItemsRelay.accept([])
        }
    }
}

extension RewardsViewModel {
    func refresh() {
        service.refresh()
    }
    
    var viewItemsDriver: Driver<[ViewItem]?> {
        viewItemsRelay.asDriver()
    }
}

extension RewardsViewModel {
    struct ViewItem {
        let date: String
        let amount: String
        
        var amountStr: String {
            "\(BigUInt(amount)?.safe4FomattedAmount ?? "__") SAFE4"
        }
    }
}

