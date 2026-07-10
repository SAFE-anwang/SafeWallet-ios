import EvmKit
import MarketKit
import RxCocoa
import RxSwift

class SendEip721ViewModel {
    private let service: SendEip721Service
    private let disposeBag = DisposeBag()

    private let proceedEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let proceedRelay = PublishRelay<SendEvmData>()
    private let nftImageRelay = BehaviorRelay<NftImage?>(value: nil)

    init(service: SendEip721Service) {
        self.service = service

        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        subscribe(disposeBag, service.nftImageObservable) { [weak self] in self?.nftImageRelay.accept($0) }
        sync(state: service.state)
        nftImageRelay.accept(service.nftImage)
    }

    private func sync(state: SendEip721Service.State) {
        if case .ready = state {
            proceedEnabledRelay.accept(true)
        } else {
            proceedEnabledRelay.accept(false)
        }
    }
}

extension SendEip721ViewModel {
    var proceedEnableDriver: Driver<Bool> {
        proceedEnabledRelay.asDriver()
    }

    var proceedSignal: Signal<SendEvmData> {
        proceedRelay.asSignal()
    }

    var nftImage: NftImage? {
        nftImageRelay.value
    }

    var nftImageDriver: Driver<NftImage?> {
        nftImageRelay.asDriver()
    }

    var name: String {
        service.assetShortMetadata?.displayName ?? "#\(service.nftUid.tokenId)"
    }

    func didTapProceed() {
        guard case let .ready(sendData) = service.state else {
            return
        }

        proceedRelay.accept(sendData)
    }
}
