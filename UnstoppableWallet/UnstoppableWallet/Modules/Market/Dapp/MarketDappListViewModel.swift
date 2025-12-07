import UIKit
import Foundation
import RxSwift
import RxRelay
import RxCocoa
import MarketKit
import SectionsTableView
import Combine

class MarketDappListViewModel: ObservableObject {
    
    private let service: MarketDappService
    private let disposeBag = DisposeBag()

    private let viewItemsRelay = BehaviorRelay<([ViewItem], MarketDappModule.Tab)?>(value: nil)
    private let loadingRelay = BehaviorRelay<Bool>(value: false)
    private let syncErrorRelay = BehaviorRelay<Bool>(value: false)

    init(service: MarketDappService) {
        self.service = service
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        sync(state: service.state)
    }

    private func sync(state: MarketDappService.State) {
        switch state {
        case .loading:
            viewItemsRelay.accept(nil)
            loadingRelay.accept(true)
            syncErrorRelay.accept(false)
        case .completed(data: (let datas, let tab)):
            viewItemsRelay.accept((datas, tab))
            loadingRelay.accept(false)
            syncErrorRelay.accept(false)
        case .failed:
            viewItemsRelay.accept(nil)
            loadingRelay.accept(false)
            syncErrorRelay.accept(true)
        }
    }



    private func timeAgo(interval: TimeInterval) -> String {
        var interval = Int(interval) / 60

        // interval from post in minutes
        if interval < 60 {
            return "timestamp.min_ago".localized(max(1, interval))
        }

        // interval in hours
        interval /= 60
        if interval < 24 {
            return "timestamp.hours_ago".localized(interval)
        }

        // interval in days
        interval /= 24
        return "timestamp.days_ago".localized(interval)
    }

}

extension MarketDappListViewModel {

    var viewItemsDriver: Driver<([ViewItem], MarketDappModule.Tab)?> {
        viewItemsRelay.asDriver()
    }

    var loadingDriver: Driver<Bool> {
        loadingRelay.asDriver()
    }

    var syncErrorDriver: Driver<Bool> {
        syncErrorRelay.asDriver()
    }

    func onLoad() {
        service.load()
    }

    func refresh() {
        service.refresh()
    }

}

extension MarketDappListViewModel {
    struct ViewItem {
        let subType: String
        let subs: [MarktDapp]
    }

}
