import RxSwift
import RxRelay
import MarketKit

class RewardsService {
    
    private var disposeBag = DisposeBag()
    private let provider: Safe4Provider
    private let address: String
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    init(provider: Safe4Provider, address: String) {
        self.provider = provider
        self.address = address
    }
    
    private func handle(datas: [Safe4Reward]) {
        let tempArr = datas.map { RewardsViewModel.ViewItem(date: $0.date, amount: $0.amount) }
        state = .completed(data: tempArr.reversed())
    }
    
    private func fetch(address: String) {
        disposeBag = DisposeBag()

        provider.getRewardsSingle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.handle(datas: datas)
            }, onError: { [weak self] error in
                self?.state = .failed(error: error)
            })
            .disposed(by: disposeBag)
    }

}

extension RewardsService {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    func refresh() {
        fetch(address: address)
    }

}
extension RewardsService {

    enum State {
        case loading
        case completed(data: [RewardsViewModel.ViewItem])
        case failed(error: Error)
    }

}
