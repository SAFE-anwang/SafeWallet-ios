import BigInt
import EvmKit
import Foundation
import Kingfisher
import MarketKit
import RxRelay
import RxSwift
import UIKit

class SendEip721Service {
    let nftUid: NftUid
    let assetShortMetadata: NftAssetShortMetadata?
    var nftImage: NftImage?
    private let adapter: INftAdapter
    private let addressService: AddressService
    private let disposeBag = DisposeBag()
    private let nftImageRelay = PublishRelay<NftImage?>()

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notReady {
        didSet {
            stateRelay.accept(state)
        }
    }

    private var addressData: AddressData?

    init(nftUid: NftUid, adapter: INftAdapter, addressService: AddressService, nftMetadataManager: NftMetadataManager, overrideAssetShortMetadata: NftAssetShortMetadata? = nil) {
        self.nftUid = nftUid
        self.adapter = adapter
        self.addressService = addressService

        assetShortMetadata = overrideAssetShortMetadata ?? nftMetadataManager.assetShortMetadata(nftUid: nftUid)
        nftImage = resolveNftImage()
        fetchNftImageIfNeeded()

        subscribe(disposeBag, addressService.stateObservable) { [weak self] in self?.sync(addressState: $0) }
    }

    private func sync(addressState: AddressService.State) {
        switch addressState {
        case let .success(address):
            do {
                addressData = try AddressData(evmAddress: EvmKit.Address(hex: address.raw), domain: address.domain)
            } catch {
                addressData = nil
            }
        default: addressData = nil
        }

        syncState()
    }

    private func syncState() {
        if case .success = addressService.state, let addressData {
            guard let transactionData = adapter.transferEip721TransactionData(contractAddress: nftUid.contractAddress, to: addressData.evmAddress, tokenId: nftUid.tokenId) else {
                state = .notReady
                return
            }
            let sendInfo = SendEvmData.SendInfo(domain: addressData.domain, assetShortMetadata: assetShortMetadata)
            let sendData = SendEvmData(transactionData: transactionData, additionalInfo: .send(info: sendInfo), warnings: [])

            state = .ready(sendData: sendData)
        } else {
            state = .notReady
        }
    }

    private func resolveNftImage() -> NftImage? {
        guard let imageUrl = assetShortMetadata?.previewImageUrl, let url = URL(string: imageUrl) else {
            return nil
        }

        if url.pathExtension == "svg", let data = try? ImageCache.default.diskStorage.value(forKey: url.absoluteString), let svgString = String(data: data, encoding: .utf8) {
            return .svg(string: svgString)
        } else if let data = try? ImageCache.default.diskStorage.value(forKey: url.absoluteString), let image = UIImage(data: data) {
            return .image(image: image)
        } else {
            return nil
        }
    }

    private func fetchNftImageIfNeeded() {
        guard nftImage == nil, let imageUrl = assetShortMetadata?.previewImageUrl, let url = URL(string: imageUrl) else {
            return
        }

        if url.pathExtension == "svg" {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    return
                }

                guard let data = try? Data(contentsOf: url), let svgString = String(data: data, encoding: .utf8) else {
                    return
                }

                try? ImageCache.default.diskStorage.store(value: data, forKey: url.absoluteString)

                DispatchQueue.main.async {
                    self.nftImage = .svg(string: svgString)
                    self.nftImageRelay.accept(self.nftImage)
                }
            }
        } else {
            KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
                guard let self, case let .success(value) = result else {
                    return
                }

                self.nftImage = .image(image: value.image)
                self.nftImageRelay.accept(self.nftImage)
            }
        }
    }
}

extension SendEip721Service {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var nftImageObservable: Observable<NftImage?> {
        nftImageRelay.asObservable()
    }
}

extension SendEip721Service {
    enum State {
        case ready(sendData: SendEvmData)
        case notReady
    }

    private struct AddressData {
        let evmAddress: EvmKit.Address
        let domain: String?
    }
}
