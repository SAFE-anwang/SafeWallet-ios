import Foundation
import RxSwift
import RxRelay
import MarketKit
import web3swift
import Web3Core
import EvmKit
import BigInt

class RewardsService {
    
    private var disposeBag = DisposeBag()
    private let provider: Safe4Provider
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    let address: String
    
    private let privateKey: Data
    private let evmKit: EvmKit.Kit
        
    private func web3() async throws -> Web3 {
        let chain = Chain.safeFourChain()
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
    
    init(provider: Safe4Provider, address: String, privateKey: Data, evmKit: EvmKit.Kit) {
        self.provider = provider
        self.address = address
        self.privateKey = privateKey
        self.evmKit = evmKit
    }
    
    private func handle(datas: [Safe4Reward]) {
        
        
    }
    
    private func fetch(address: String) {
        disposeBag = DisposeBag()

        provider.getRewardsSingle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.state = .completed(data: datas.reversed())
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
    
    func withdrawByID() async throws -> String {
        try await web3().safe4.accountmanager.withdrawByID(privateKey: privateKey, ids: [0])
    }

}
extension RewardsService {

    enum State {
        case loading
        case completed(data: [Safe4Reward])
        case failed(error: Error)
    }

}
