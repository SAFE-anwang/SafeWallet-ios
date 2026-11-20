import EvmKit
import Foundation
import RxSwift

public class EvmLabelManager {
    private let keyMethodLabelsTimestamp = "evm-label-manager-method-labels-timestamp"
    private let keyAddressLabelsTimestamp = "evm-label-manager-address-labels-timestamp"

    private let provider: HsLabelProvider
    private let storage: EvmLabelStorage
    private let syncerStateStorage: SyncerStateStorage
    private let disposeBag = DisposeBag()
    private let methodLabelsUpdatedSubject = PublishSubject<Void>()
    private let src721RecognitionScheduler = SRC721ContractRecognitionScheduler.shared

    public init(provider: HsLabelProvider, storage: EvmLabelStorage, syncerStateStorage: SyncerStateStorage) {
        self.provider = provider
        self.storage = storage
        self.syncerStateStorage = syncerStateStorage

        NotificationCenter.default.rx.notification(.src721ContractRecognitionUpdated)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in self?.methodLabelsUpdatedSubject.onNext(()) })
            .disposed(by: disposeBag)
    }

    private func syncMethodLabels(timestamp: Int) {
        if let rawLastSyncTimestamp = try? syncerStateStorage.value(key: keyMethodLabelsTimestamp), let lastSyncTimestamp = Int(rawLastSyncTimestamp), timestamp == lastSyncTimestamp {
            return
        }

        provider.evmMethodLabelsSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] labels in
                try? self?.storage.save(evmMethodLabels: labels)
                self?.saveMethodLabels(timestamp: timestamp)
                self?.methodLabelsUpdatedSubject.onNext(())
            }, onError: { error in
                print("Method Labels sync error: \(error)")
            })
            .disposed(by: disposeBag)
    }

    private func syncAddressLabels(timestamp: Int) {
        if let rawLastSyncTimestamp = try? syncerStateStorage.value(key: keyAddressLabelsTimestamp), let lastSyncTimestamp = Int(rawLastSyncTimestamp), timestamp == lastSyncTimestamp {
            return
        }

        provider.evmAddressLabelsSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] labels in
                try? self?.storage.save(evmAddressLabels: labels)

                self?.saveAddressLabels(timestamp: timestamp)
            }, onError: { error in
                print("Address Labels sync error: \(error)")
            })
            .disposed(by: disposeBag)
    }

    private func saveMethodLabels(timestamp: Int) {
        try? syncerStateStorage.save(value: String(timestamp), key: keyMethodLabelsTimestamp)
    }

    private func saveAddressLabels(timestamp: Int) {
        try? syncerStateStorage.save(value: String(timestamp), key: keyAddressLabelsTimestamp)
    }
}

extension EvmLabelManager {
    var methodLabelsUpdatedObservable: Observable<Void> {
        methodLabelsUpdatedSubject.asObservable().observeOn(MainScheduler.instance)
    }

    func sync() {
        provider.updateStatusSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] status in
                self?.syncMethodLabels(timestamp: status.methodLabels)
                self?.syncAddressLabels(timestamp: status.addressLabels)
            }, onError: { error in
                print("Update Status sync error: \(error)")
            })
            .disposed(by: disposeBag)
    }

    func methodLabel(input: Data) -> String? {
        let methodId = Data(input.prefix(4)).hs.hexString
        return methodLabel(methodId: methodId)
    }

    func methodLabel(input: Data, contractAddress: String?, chainId: Int?, walletAddress: String?) -> String? {
        let methodId = Data(input.prefix(4)).hs.hexString
        if let customLabel = src721MethodLabel(
            input: input,
            contractAddress: contractAddress,
            chainId: chainId,
            walletAddress: walletAddress
        ) { return customLabel }

        return methodLabel(methodId: methodId)
    }

    func src721MethodLabel(input: Data, contractAddress: String?, chainId: Int?, walletAddress: String? = nil) -> String? {
        let methodId = Data(input.prefix(4)).hs.hexString
        guard let label = SRC721TransactionLabel.method(methodId: methodId),
              let chainId,
              let contractAddress else {
            return nil
        }

        let storage = SRC721Storage.shared
        if storage.containsContract(chainId: chainId, contractAddress: contractAddress) ||
            (walletAddress.map { storage.containsContract(chainId: chainId, walletAddress: $0, contractAddress: contractAddress) } ?? false) {
            return label.title
        }

        if let isSRC721 = storage.recognizedSRC721Contract(chainId: chainId, contractAddress: contractAddress) {
            return isSRC721 ? label.title : nil
        }

        return nil
    }

    func scheduleSRC721MethodRecognition(input: Data?, contractAddress: String?, chainId: Int?, walletAddress: String?) {
        guard let input else { return }
        guard SRC721TransactionLabel.method(methodId: Data(input.prefix(4)).hs.hexString) != nil,
              let chainId,
              let contractAddress else {
            return
        }

        let storage = SRC721Storage.shared
        if storage.containsContract(chainId: chainId, contractAddress: contractAddress) ||
            (walletAddress.map { storage.containsContract(chainId: chainId, walletAddress: $0, contractAddress: contractAddress) } ?? false) ||
            storage.recognizedSRC721Contract(chainId: chainId, contractAddress: contractAddress) != nil {
            return
        }

        let candidate = SRC721ContractRecognitionScheduler.Candidate.contract(
            chainId: chainId,
            address: contractAddress.lowercased()
        )
        Task(priority: .utility) { [src721RecognitionScheduler] in
            await src721RecognitionScheduler.schedule(candidate)
        }
    }

    func contractCreationLabel(chainId: Int?, walletAddress: String, transactionHash: String) -> String? {
        guard let chainId else {
            return nil
        }

        let storage = SRC721Storage.shared
        if storage.containsDeployment(chainId: chainId, walletAddress: walletAddress, transactionHash: transactionHash) {
            return SRC721TransactionLabel.creation.title
        }

        return nil
    }

    private func methodLabel(methodId: String) -> String? {
        let label = EvmKit.Safe4Methods.allCases.first { $0.id.lowercased() == methodId.lowercased() }?.title
            ?? EvmLabelManager.ExSafe4Methods.allCases.first { $0.id.lowercased() == methodId.lowercased() }?.title
        return label ?? (try? storage.evmMethodLabel(methodId: methodId))?.label
    }

    func addressLabel(address: String) -> String? {
        (try? storage.evmAddressLabel(address: address.lowercased()))?.label
    }

    func mapped(address: String) -> String {
        if let label = addressLabel(address: address) {
            return label
        }

        return address.shortened
    }

    func addressLabelMap() -> [String: String] {
        do {
            let addressLabels = try storage.allAddressLabels()
            return addressLabels.reduce(into: [String: String]()) { $0[$1.address] = $1.label }
        } catch {
            return [:]
        }
    }
}
