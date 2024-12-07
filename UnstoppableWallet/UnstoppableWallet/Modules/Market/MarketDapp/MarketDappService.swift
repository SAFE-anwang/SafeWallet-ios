import RxSwift
import RxRelay
import MarketKit

class MarketDappService {
    
    private var disposeBag = DisposeBag()
    private let dappProvider: MarketDappProvider
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }

    init(provider: MarketDappProvider) {
        self.dappProvider = provider
    }
    
    private func handle(datas: [MarktDapp], tab: MarketDappModule.Tab) {
        let tempArr = Dictionary(grouping: datas) { $0.subType }.map { (key: String, value: [MarktDapp]) in
            return MarketDappViewModel.ViewItem(subType: key, subs: value)
        }
        state = .completed(data: (tempArr, tab))
    }
    
    private func fetch(_ tab: MarketDappModule.Tab) {
        disposeBag = DisposeBag()
        if case .failed = state {
            state = .loading
        }
        
        let single: Single<[MarktDapp]>
        switch tab {
        case .ALL:
            single = dappProvider.dappAllRequestSingle()
        case .ETH:
            single = dappProvider.dappSubTypeRequestSingle(subType: "ETH")
        case .BSC:
            single = dappProvider.dappSubTypeRequestSingle(subType: "BSC")
        case .SAFE:
            single = dappProvider.dappSubTypeRequestSingle(subType: "SAFE")
        }
        
        single
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.handle(datas: datas, tab: tab)
            }, onError: { [weak self] error in
                self?.state = .failed(error: error)
            })
            .disposed(by: disposeBag)
    }

}

extension MarketDappService {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    func load(tab: MarketDappModule.Tab) {
        fetch(tab)
    }

    func refresh(tab: MarketDappModule.Tab) {
        fetch(tab)
    }

}
extension MarketDappService {

    enum State {
        case loading
        case completed(data: (datas:[MarketDappViewModel.ViewItem], tab: MarketDappModule.Tab))
        case failed(error: Error)
    }
}


