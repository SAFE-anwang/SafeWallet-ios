import Foundation
import MarketKit
import RxRelay
import RxSwift

class NftAdapterManager {
    private let walletManager: WalletManager
    private let accountManager: AccountManager
    private let evmBlockchainManager: EvmBlockchainManager
    private let disposeBag = DisposeBag()

    private let adaptersUpdatedRelay = PublishRelay<[NftKey: INftAdapter]>()
    private var _adapterMap = [NftKey: INftAdapter]()

    private let queue = DispatchQueue(label: "\(AppConfig.label).nft-adapter_manager", qos: .userInitiated)

    init(walletManager: WalletManager, accountManager: AccountManager, evmBlockchainManager: EvmBlockchainManager) {
        self.walletManager = walletManager
        self.accountManager = accountManager
        self.evmBlockchainManager = evmBlockchainManager

        walletManager.activeWalletDataUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] walletData in
                self?.handleAdaptersReady(wallets: walletData.wallets, account: walletData.account)
            })
            .disposed(by: disposeBag)

        for blockchain in evmBlockchainManager.allBlockchains {
            if let manager = try? evmBlockchainManager.evmKitManager(blockchainType: blockchain.type) {
                subscribe(disposeBag, manager.evmKitUpdatedObservable) { [weak self] in
                    self?.handleUpdatedEvmKit(blockchainType: blockchain.type)
                }
            }
        }

        _initAdapters(wallets: walletManager.activeWallets, account: accountManager.activeAccount)
    }

    private func _initAdapters(wallets: [Wallet], account: Account?) {
        guard let account else {
            _adapterMap = [:]
            adaptersUpdatedRelay.accept(_adapterMap)
            return
        }

        var blockchainTypes = Set(wallets.map { $0.token.blockchainType })
        for blockchainType in EvmBlockchainManager.blockchainTypes where !blockchainType.supportedNftTypes.isEmpty {
            blockchainTypes.insert(blockchainType)
        }

        let nftKeys = Array(Set(blockchainTypes.map { NftKey(account: account, blockchainType: $0) }))

        var newAdapterMap = [NftKey: INftAdapter]()

        for nftKey in nftKeys {
            if let adapter = _adapterMap[nftKey] {
                newAdapterMap[nftKey] = adapter
                continue
            }

            guard !nftKey.blockchainType.supportedNftTypes.isEmpty else {
                continue
            }

            if evmBlockchainManager.blockchain(type: nftKey.blockchainType) != nil {
                let evmKitWrapper = try? evmBlockchainManager.evmKitManager(blockchainType: nftKey.blockchainType).evmKitWrapper(account: nftKey.account, blockchainType: nftKey.blockchainType)

                if let evmKitWrapper, let nftKit = evmKitWrapper.nftKit {
                    newAdapterMap[nftKey] = EvmNftAdapter(blockchainType: nftKey.blockchainType, evmKitWrapper: evmKitWrapper, nftKit: nftKit)
                }
            } else {
                // Init other blockchain adapter here (e.g. Solana)
            }
        }

//        print("NEW ADAPTERS: \(newAdapterMap.keys)")
        _adapterMap = newAdapterMap
        adaptersUpdatedRelay.accept(newAdapterMap)
    }

    private func handleAdaptersReady(wallets: [Wallet], account: Account?) {
        queue.async {
            self._initAdapters(wallets: wallets, account: account)
        }
    }

    private func handleUpdatedEvmKit(blockchainType: BlockchainType) {
        queue.async {
            guard let account = self.accountManager.activeAccount else {
                return
            }

            self._adapterMap = self._adapterMap.filter { key, _ in
                !(key.account == account && key.blockchainType == blockchainType)
            }
            self._initAdapters(wallets: self.walletManager.activeWallets, account: account)
        }
    }
}

extension NftAdapterManager {
    var adapterMap: [NftKey: INftAdapter] {
        queue.sync { _adapterMap }
    }

    var adaptersUpdatedObservable: Observable<[NftKey: INftAdapter]> {
        adaptersUpdatedRelay.asObservable()
    }

    func adapter(nftKey: NftKey) -> INftAdapter? {
        queue.sync { _adapterMap[nftKey] }
    }

    func refresh() {
        queue.async {
            for adapter in self._adapterMap.values {
                adapter.sync()
            }
        }
    }
}
