import RxSwift
import RxRelay
import MarketKit

class CoinTweetsService {
    private let disposeBag = DisposeBag()
    private let twitterProvider: TweetsProvider
    private let marketKit: MarketKit.Kit
    private var coinUid: String
    private var userName: String? = nil
    
    private var user: TwitterUser? = nil
    private let stateRelay = PublishRelay<DataStatus<[Tweet]>>()

    private(set) var state: DataStatus<[Tweet]> = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(coinUid: String, twitterProvider: TweetsProvider, marketKit: MarketKit.Kit) {
        self.coinUid = coinUid
        self.twitterProvider = twitterProvider
        self.marketKit = marketKit
    }
    
    init(userName: String, twitterProvider: TweetsProvider, marketKit: MarketKit.Kit) {
        self.userName = userName
        self.coinUid = ""
        self.twitterProvider = twitterProvider
        self.marketKit = marketKit
    }

    private func handle(tweets: [Tweet]) {
        state = .completed(tweets)
    }

}

extension CoinTweetsService {

    var stateObservable: Observable<DataStatus<[Tweet]>> {
        stateRelay.asObservable()
    }

    var username: String? {
        user?.username
    }

    func fetch() {
        if case .failed = state {
            state = .loading
        }

        let single: Single<TwitterUser?>
        
        if let user = user {
            single = Single.just(user)
        }else if let username = userName, !username.isEmpty {
            single = twitterProvider.userRequestSingle(username: username)
        }else {
            single = marketKit
                    .twitterUsername(coinUid: coinUid)
                    .flatMap { [weak self] username in
                        guard let service = self, let username = username, !username.isEmpty else {
                            return Single.just(nil)
                        }

                        return service.twitterProvider.userRequestSingle(username: username)
                    }
        }

        single
                .flatMap { [weak self] (user: TwitterUser?) -> Single<TweetsProvider.TweetsPage> in
                    guard let user = user, let service = self else {
                        return Single.error(LoadError.tweeterUserNotFound)
                    }

                    service.user = user

                    return service.twitterProvider.tweetsSingle(user: user)
                }
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(
                        onSuccess: { [weak self] tweetsPage in
                            self?.handle(tweets: tweetsPage.tweets)
                        },
                        onError: { [weak self] error in
                            self?.state = .failed(error)
                        }
                )
                .disposed(by: disposeBag)
    }

}

extension CoinTweetsService {

    enum LoadError: Error {
        case tweeterUserNotFound
    }

}
