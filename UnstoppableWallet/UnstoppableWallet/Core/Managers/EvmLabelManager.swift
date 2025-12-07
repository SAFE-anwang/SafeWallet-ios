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
        let label = EvmKit.Safe4Methods.allCases.filter{$0.id.lowercased() == methodId.lowercased()}.first?.title ?? EvmLabelManager.ExSafe4Methods.allCases.filter{$0.id.lowercased() == methodId.lowercased()}.first?.title
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

extension EvmLabelManager {
    enum ExSafe4Methods: CaseIterable {
        case addLiquidity
        case addEthLiquidity
        case removeLiquidity
        case removeLiquidityPermit
        case lineLock
        case promotion
        case deploy_0
        case deploy_1
        case destroy
        case removeVote
        case src20Lock
        
        var id: String {
            switch self {
            case .addLiquidity: "0xe8e33700"
            case .addEthLiquidity: "0xf305d719"
            case .removeLiquidity: "0xbaa2abde"
            case .removeLiquidityPermit: "0x2195995c"
            case .lineLock: "0x9c4ee6bf"
            case .promotion: "0x198581a5"
            case .deploy_0: "0x40c10f19"
            case .deploy_1: "0x61016060"
            case .destroy: "0x42966c68"
            case .removeVote : "0x9fbe5cc5"
            case .src20Lock: "0x4b86c225"
            }
        }
        
        var title: String {
            switch self {
            case .addLiquidity, .addEthLiquidity: "liquidity.title.add".localized
            case .removeLiquidity, .removeLiquidityPermit: "liquidity.remove".localized
            case .lineLock: "safe_zone.row.linear".localized
            case .promotion: "SRC20_Info_Promotion".localized
            case .deploy_0, .deploy_1: "SRC20_Deploy_Title".localized
            case .destroy: "SRC20_Info_Destroy".localized
            case .removeVote: "取消投票和委托".localized
            case .src20Lock: "SRC20 锁仓".localized
            }
        }
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
        case .BatchRedeemLocked: "safe_zone.safe4.contract.batchRedeem.locked".localized
        case .BatchRedeemAvailable: "safe_zone.safe4.contract.batchRedeem.available".localized
        case .Eth2safe: "safe_zone.safe4.contract.crossChain".localized
        case .safe4ToBsc, .safe4ToEth, .safe4ToPol, .bscToSafe4, .ethToSafe4, .polToSafe4: "safe_zone.safe4.contract.crossChain".localized
        case .Safe4SwapSrc, .SrcSwapSafe4: "swap.safe4.title".localized
        }
    }
}
