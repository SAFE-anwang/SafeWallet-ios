import Combine
import Foundation

public class TransactionAdapterManager {
    private var cancellables = Set<AnyCancellable>()
    // serial: replaces the SerialDispatchQueueScheduler the Rx subscription used
    private let initQueue = DispatchQueue(label: "\(AppConfig.label).transaction-adapter-manager", qos: .userInitiated)

    private let adapterManager: AdapterManager
    private let evmBlockchainManager: EvmBlockchainManager
    private let adapterFactory: AdapterFactory

    private let adaptersReadySubject = PassthroughSubject<Void, Never>()

    private let queue = DispatchQueue(label: "\(AppConfig.label).transactions_adapter_manager", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()
    private var _adapterMap = [TransactionSource: ITransactionsAdapter]()

    public init(adapterManager: AdapterManager, evmBlockchainManager: EvmBlockchainManager, adapterFactory: AdapterFactory) {
        self.adapterManager = adapterManager
        self.evmBlockchainManager = evmBlockchainManager
        self.adapterFactory = adapterFactory
        queue.setSpecific(key: queueKey, value: ())

        adapterManager.adapterDataReadyPublisher
            .receive(on: initQueue)
            .sink { [weak self] adapterData in
                self?.initAdapters(adapterMap: adapterData.adapterMap)
            }
            .store(in: &cancellables)
    }

    private func initAdapters(adapterMap: [Wallet: IAdapter]) {
        var newAdapterMap = [TransactionSource: ITransactionsAdapter]()

        for (wallet, adapter) in adapterMap {
            let source = wallet.transactionSource

            guard newAdapterMap[source] == nil else {
                continue
            }

            let transactionsAdapter: ITransactionsAdapter?

            if evmBlockchainManager.allBlockchains.contains(where: { $0.type == source.blockchainType }) {
                if let evmAdapter = adapter as? BaseEvmAdapter {
                    transactionsAdapter = adapterFactory.evmTransactionsAdapter(transactionSource: source, evmKitWrapper: evmAdapter.evmKitWrapper)
                } else {
                    transactionsAdapter = nil
                }
            } else if source.blockchainType == .tron {
                if let tronAdapter = adapter as? BaseTronAdapter {
                    transactionsAdapter = adapterFactory.tronTransactionsAdapter(transactionSource: source, tronKitWrapper: tronAdapter.tronKitWrapper)
                } else {
                    transactionsAdapter = nil
                }
            } else if source.blockchainType == .thorChain || source.blockchainType == .mayaChain {
                if let thorChainAdapter = adapter as? ThorChainAdapter {
                    transactionsAdapter = adapterFactory.thorChainTransactionsAdapter(transactionSource: source, thorChainKitWrapper: thorChainAdapter.thorChainKitWrapper)
                } else {
                    transactionsAdapter = nil
                }
            } else if source.blockchainType == .ton {
                transactionsAdapter = adapterFactory.tonTransactionAdapter(transactionSource: source)
            } else if source.blockchainType == .stellar {
                transactionsAdapter = adapterFactory.stellarTransactionAdapter(transactionSource: source)
            } else if source.blockchainType == .solana {
                transactionsAdapter = adapterFactory.solanaTransactionsAdapter(transactionSource: source)
            } else if source.blockchainType == .xrp {
                transactionsAdapter = adapterFactory.xrpTransactionAdapter(transactionSource: source)
            } else if source.blockchainType == .near {
                transactionsAdapter = adapterFactory.nearTransactionAdapter(transactionSource: source)
            } else {
                transactionsAdapter = adapter as? ITransactionsAdapter
            }

            if let transactionsAdapter {
                newAdapterMap[source] = transactionsAdapter
            }
        }

        queue.async {
            self._adapterMap = newAdapterMap
            self.adaptersReadySubject.send(())
        }
    }
}

public extension TransactionAdapterManager {
    internal var adapterMap: [TransactionSource: ITransactionsAdapter] {
        queue.sync { _adapterMap }
    }

    var adaptersReadyPublisher: AnyPublisher<Void, Never> {
        adaptersReadySubject.eraseToAnyPublisher()
    }

    func adapter(for source: TransactionSource) -> ITransactionsAdapter? {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return _adapterMap[source]
        }

        return queue.sync { _adapterMap[source] }
    }
}
