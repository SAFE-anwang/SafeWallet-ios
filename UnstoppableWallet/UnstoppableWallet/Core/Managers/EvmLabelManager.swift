import EvmKit
import Foundation
import RxSwift

class EvmLabelManager {
    private let keyMethodLabelsTimestamp = "evm-label-manager-method-labels-timestamp"
    private let keyAddressLabelsTimestamp = "evm-label-manager-address-labels-timestamp"

    private let provider: HsLabelProvider
    private let storage: EvmLabelStorage
    private let syncerStateStorage: SyncerStateStorage
    private let disposeBag = DisposeBag()

    init(provider: HsLabelProvider, storage: EvmLabelStorage, syncerStateStorage: SyncerStateStorage) {
        self.provider = provider
        self.storage = storage
        self.syncerStateStorage = syncerStateStorage
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
        let label = EvmKit.Safe4Methods.allCases.filter{$0.id == methodId}.first?.title
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
}

extension EvmKit.Safe4Methods {
    
    var title: String {
        switch self {
        case .AppendRegister: "safe_zone.safe4.appendRegister".localized
        case .Withdraw: "safe_zone.safe4.withdraw".localized
        case .WithdrawByID: "safe_zone.safe4.WithdrawByID".localized
        case .CreateProposal: "safe_zone.safe4.CreateProposal".localized
        case .VoteSuperNode: "safe_zone.safe4.VoteSuperNode".localized
        case .MasterNodeRegister: "safe_zone.safe4.MasterNodeRegister".localized
        case .SuperNodeRegister: "safe_zone.safe4.SuperNodeRegister".localized
        case .NodeUpdateDesc: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateEnode: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateName: "safe_zone.safe4.NodeUpdate".localized
        case .NodeUpdateAddress: "safe_zone.safe4.NodeUpdate".localized
        case .LockVote: "safe_zone.safe4.lockVote".localized
        case .Reward: "safe_zone.safe4.reward".localized
        case .RedeemMsaternode: "safe_zone.safe4.redeem.msaternode".localized
        case .RedeemLocked: "safe_zone.safe4.redeem.locked".localized
        case .RedeemAvailable: "safe_zone.safe4.redeem.available".localized
        case .NodeStateUpload: "safe_zone.safe4.node.state.upload".localized
        case .ProposalVote: "safe_zone.safe4.ProposalVote".localized
        case .ContractDeployment: "safe_zone.safe4.contract.deployment".localized
        case .AddLockDay: "safe_zone.safe4.contract.addlockday".localized
        }
    }
}
