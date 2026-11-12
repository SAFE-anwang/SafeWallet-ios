import Foundation
import RxSwift
import RxRelay
import MarketKit
import web3swift
import Web3Core
import EvmKit
import BigInt

class RewardsService {
    let networkSession = Safe4NetworkSession()

    private var disposeBag = DisposeBag()
    private var networkObservation: Safe4NetworkSession?
    private let provider: Safe4Provider
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }

    var cacheScope: Safe4CacheScope {
        Safe4CacheScope(chainId: evmKit.chain.id, owner: address)
    }

    let address: String

    private let privateKey: Data
    private let evmKit: EvmKit.Kit

    private func web3() async throws -> Web3 {
        let context = try Safe4Network.activeContext(chainId: evmKit.chain.id)
        try networkSession.check()
        try Task.checkCancellation()
        let web3 = try await Web3.new(context.rpcUrl, network: Networks.Custom(networkID: BigUInt(context.chainId)))
        try networkSession.check()
        try Task.checkCancellation()
        _ = try Safe4Network.activeContext(chainId: context.chainId)
        return web3
    }

    init(provider: Safe4Provider, address: String, privateKey: Data, evmKit: EvmKit.Kit) {
        self.provider = provider
        self.address = address
        self.privateKey = privateKey
        self.evmKit = evmKit
        networkObservation = Safe4NetworkSession { [weak self] in
            self?.disposeBag = DisposeBag()
        }
    }

    private func handle(datas: [Safe4Reward]) {

    }

    private func fetch(address: String) {

        guard networkSession.isValid else { return }
        disposeBag = DisposeBag()
        provider.getRewardsSingle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] datas in
                guard self?.networkSession.isValid == true else { return }
                self?.state = .completed(data: datas.reversed())
            }, onError: { [weak self] error in
                guard self?.networkSession.isValid == true else { return }
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

    func withdrawByID() async throws {
        _ = try await web3().safe4.accountmanager(type: .native).withdrawByID(privateKey: privateKey, ids: [0])
        _ = try await web3().safe4.accountmanager(type: .smallAmount_01).withdrawByID(privateKey: privateKey, ids: [0])
        _ = try await web3().safe4.accountmanager(type: .smallAmount_02).withdrawByID(privateKey: privateKey, ids: [0])
    }

}
extension RewardsService {

    enum State {
        case loading
        case completed(data: [Safe4Reward])
        case failed(error: Error)
    }

}
