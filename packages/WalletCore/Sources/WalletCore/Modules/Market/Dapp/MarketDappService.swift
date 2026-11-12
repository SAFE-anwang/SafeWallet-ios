import Foundation
import BigInt
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
        for dapp in datas where Self.isDisplayable(dapp) {
            let group = MarketDappProvider.isSafeDapp(dapp) ? "SAFE DAPP" : "DEX"
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

        let updates: Observable<AllDappsUpdate>
        switch tab {
        case .ALL:
            updates = allDappsUpdates()
        case .ETH:
            updates = dappProvider.dappTypeRequestSingle(type: "ETH").asObservable().map(AllDappsUpdate.api)
        case .BSC:
            updates = dappProvider.dappTypeRequestSingle(type: "BSC").asObservable().map(AllDappsUpdate.api)
        case .SAFE:
            updates = safeDappsUpdates().map(AllDappsUpdate.safe)
        }

        var apiDapps: [MarktDapp]? = tab == .SAFE ? [] : nil
        var safeDapps: [MarktDapp] = []

        updates
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .observeOn(SerialDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] update in
                switch update {
                case .api(let dapps):
                    apiDapps = dapps
                case .safe(let dapps):
                    safeDapps = dapps
                }

                guard let apiDapps else { return }
                let dapps = tab == .SAFE ? safeDapps : Self.merge(apiDapps: apiDapps, safeDapps: safeDapps)
                self?.handle(datas: dapps, tab: tab)
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
    func allDappsUpdates() -> Observable<AllDappsUpdate> {
        let apiUpdates = dappProvider.dappAllRequestSingle()
            .asObservable()
            .map(AllDappsUpdate.api)
        let safeUpdates = safeDappsUpdates()
            .map(AllDappsUpdate.safe)
            .catchError { _ in Observable<AllDappsUpdate>.empty() }

        return Observable.merge(apiUpdates, safeUpdates)
    }

    func safeDappsUpdates() -> Observable<[MarktDapp]> {
        Observable.create { observer in
            let task = Task {
                do {
                    let (chainId, address) = await MainActor.run {
                        (Safe4Network.currentChainId, ChildWalletBridge.shared.activeSafe4EvmKitWrapper()?.evmKit.receiveAddress.hex)
                    }
                    var mineIDs = Set<BigUInt>()
                    if let address {
                        // If ownership cannot be verified, only promoted entries are public.
                        mineIDs = (try? await SafeDappService.mineDappIDs(address: address, chainId: chainId)) ?? []
                    }
                    try Task.checkCancellation()
                    let visibleMineIDs = mineIDs
                    _ = try await SafeDappService.publishedDappItems(chainId: chainId, onItemsUpdated: { items in
                        observer.onNext(Self.marketDapps(from: items, mineIDs: visibleMineIDs))
                    })
                    observer.onCompleted()
                } catch {
                    observer.onError(error)
                }
            }
            return Disposables.create {
                task.cancel()
            }
        }
    }

}

extension MarketDappService {
    static func marketDapps(from items: [SafeDappPublishedItem], mineIDs: Set<BigUInt>) -> [MarktDapp] {
        // Match Android: an uploaded logo means promoted; unpublished logos
        // (including an in-flight logo read) are visible only to the issuer.
        items.filter { mineIDs.contains($0.info.id) || !($0.logoData?.isEmpty ?? true) }.map {
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
    }

}

extension MarketDappService {
    static func merge(apiDapps: [MarktDapp], safeDapps: [MarktDapp]) -> [MarktDapp] {
        let existingKeys = Set(apiDapps.map { "\($0.name)|\($0.dlink)" })
        let additionalSafeDapps = safeDapps.filter { !existingKeys.contains("\($0.name)|\($0.dlink)") }
        return apiDapps + additionalSafeDapps
    }

    static func isDisplayable(_ dapp: MarktDapp) -> Bool {
        // SAFE DApps come from the chain registry; do not discard their published data here.
        if MarketDappProvider.isSafeDapp(dapp) {
            return true
        }

        guard
            !dapp.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            MarketDappModule.normalizedUrl(from: dapp.dlink) != nil
        else {
            return false
        }

        return true
    }

}

private enum AllDappsUpdate {
    case api([MarktDapp])
    case safe([MarktDapp])
}

extension MarketDappService {

    enum State {
        case loading
        case completed(data: (datas:[MarketDappListViewModel.ViewItem], tab: MarketDappModule.Tab))
        case failed(error: Error)
    }
}
