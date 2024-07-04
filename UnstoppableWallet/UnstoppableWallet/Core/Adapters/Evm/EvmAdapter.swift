import BigInt
import Eip20Kit
import EvmKit
import HsToolKit
import RxSwift
import UniswapKit

class EvmAdapter: BaseEvmAdapter {
    static let decimals = 18

    init(evmKitWrapper: EvmKitWrapper) {
        super.init(evmKitWrapper: evmKitWrapper, decimals: EvmAdapter.decimals)
    }
}

extension EvmAdapter {
    static func clear(except excludedWalletIds: [String]) throws {
        try EvmKit.Kit.clear(exceptFor: excludedWalletIds)
    }
}

// IAdapter
extension EvmAdapter: IAdapter {
    func start() {
        // started via EvmKitManager
    }

    func stop() {
        // stopped via EvmKitManager
    }

    func refresh() {
        // refreshed via EvmKitManager
    }
}

extension EvmAdapter: IBalanceAdapter {
    var balanceState: AdapterState {
        convertToAdapterState(evmSyncState: evmKit.syncState)
    }

    var balanceStateUpdatedObservable: Observable<AdapterState> {
        evmKit.syncStateObservable.map { [weak self] in
            self?.convertToAdapterState(evmSyncState: $0) ?? .syncing(progress: nil, lastBlockDate: nil)
        }
    }

    var balanceData: BalanceData {
        let available = balanceData(balance: evmKit.accountState?.balance).available
        let locked = balanceData(balance: evmKit.accountState?.timeLockBalance).available

        return LockedBalanceData(
            available: available,
            locked: locked
        )
    }

    var balanceDataUpdatedObservable: Observable<BalanceData> {
        evmKit.accountStateObservable.map { [weak self] in
            if let available = self?.balanceData(balance: $0.balance).available,
               let locked = self?.balanceData(balance: $0.timeLockBalance).available {
                return LockedBalanceData(available: available, locked: locked)
            }else {
                return BalanceData(available: 0)
            }
        }
    }
}

extension EvmAdapter: ISendEthereumAdapter {
    func transactionData(amount: BigUInt, address: EvmKit.Address) -> TransactionData {
        evmKit.transferTransactionData(to: address, value: amount)
    }
}
