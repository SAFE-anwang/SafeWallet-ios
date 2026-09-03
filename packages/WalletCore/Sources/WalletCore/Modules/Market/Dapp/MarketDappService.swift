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
    private let currentTab: MarketDappModule.Tab

    init(provider: MarketDappProvider, currentTab: MarketDappModule.Tab) {
        self.dappProvider = provider
        self.currentTab = currentTab
    }

    private func handle(datas: [MarktDapp], tab: MarketDappModule.Tab) {
        var grouped: [String: [MarktDapp]] = [:]
        for dapp in datas {
            let group = dapp.type.caseInsensitiveCompare("SAFE") == .orderedSame ? "SAFE DAPP" : "DEX"
            grouped[group, default: []].append(dapp)
        }
        let tempArr = ["DEX", "SAFE DAPP"].compactMap { group -> MarketDappListViewModel.ViewItem? in
            guard let dapps = grouped[group], !dapps.isEmpty else { return nil }
            return MarketDappListViewModel.ViewItem(subType: group, subs: dapps)
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
            single = allDappsSingle()
        case .ETH:
            single = dappProvider.dappTypeRequestSingle(type: "ETH")
        case .BSC:
            single = dappProvider.dappTypeRequestSingle(type: "BSC")
        case .SAFE:
            single = safeDappsSingle()
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

    func load() {
        fetch(currentTab)
    }

    func refresh() {
        fetch(currentTab)
    }

}

private extension MarketDappService {
    func allDappsSingle() -> Single<[MarktDapp]> {
        Single.zip(
            dappProvider.dappAllRequestSingle(),
            safeDappsSingle().catchErrorJustReturn([])
        ) { apiDapps, safeDapps in
            let existingKeys = Set(apiDapps.map(Self.dappKey))
            let additionalSafeDapps = safeDapps.filter { !existingKeys.contains(Self.dappKey($0)) }
            return apiDapps + additionalSafeDapps
        }
    }

    func safeDappsSingle() -> Single<[MarktDapp]> {
        Single.create { single in
            let task = Task {
                do {
                    let items = try await SafeDappService.publishedDappItems()
                    let dapps = items.map {
                        MarktDapp(
                            type: "SAFE",
                            subType: "SAFE DAPP",
                            name: $0.info.name,
                            desc: $0.info.description,
                            descEN: $0.info.description,
                            icon: "",
                            dlink: $0.info.runUrl,
                            md5Code: $0.info.id.description,
                            keywords: $0.info.keyword,
                            chainId: $0.info.id.description,
                            safeDappId: $0.info.id,
                            safeDappContractAddr: $0.info.contractAddr.address,
                            safeDappKeyword: $0.info.keyword,
                            safeDappFraudNum: $0.info.fraudNum,
                            safeDappIsFrozen: $0.info.isFrozen,
                            safeDappLogoData: $0.logoData
                        )
                    }
                    single(.success(dapps))
                } catch {
                    single(.error(error))
                }
            }
            return Disposables.create {
                task.cancel()
            }
        }
    }

    static func dappKey(_ dapp: MarktDapp) -> String {
        "\(dapp.name)|\(dapp.dlink)"
    }
}
extension MarketDappService {

    enum State {
        case loading
        case completed(data: (datas:[MarketDappListViewModel.ViewItem], tab: MarketDappModule.Tab))
        case failed(error: Error)
    }
}
