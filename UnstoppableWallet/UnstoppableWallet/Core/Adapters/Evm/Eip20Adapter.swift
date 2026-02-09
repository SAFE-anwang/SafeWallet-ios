import BigInt
import Combine
import Eip20Kit
import EvmKit
import Foundation
import HsToolKit
import MarketKit
import RxSwift

class Eip20Adapter: BaseEvmAdapter {
    private static let approveConfirmationsThreshold: Int? = nil
    let eip20Kit: Eip20Kit.Kit
    private let contractAddress: EvmKit.Address
    private let transactionConverter: EvmTransactionConverter
    private let balanceDataSubject = PublishSubject<BalanceData>()
    private var lockedAmount: Decimal = 0
    private var lockedAmountCancellable: AnyCancellable?
    private var lockedService: SRC20LockedService?
    
    init(evmKitWrapper: EvmKitWrapper, contractAddress: String, wallet: Wallet, baseToken: Token, coinManager: CoinManager, evmLabelManager: EvmLabelManager) throws {
        let address = try EvmKit.Address(hex: contractAddress)
        eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: address)
        self.contractAddress = address

        transactionConverter = EvmTransactionConverter(
            source: wallet.transactionSource, baseToken: baseToken, coinManager: coinManager, evmKitWrapper: evmKitWrapper, blockchainType: evmKitWrapper.blockchainType,
            userAddress: evmKitWrapper.evmKit.address, evmLabelManager: evmLabelManager
        )
        super.init(evmKitWrapper: evmKitWrapper, decimals: wallet.decimals)
        synceSrc20LockedRecord()
    }
}

// IAdapter

extension Eip20Adapter: IAdapter {
    func start() {
        eip20Kit.start()
    }

    func stop() {
        eip20Kit.stop()
    }

    func refresh() {
        start()
        synceSrc20LockedRecord()
    }
}

extension Eip20Adapter: IBalanceAdapter {
    var balanceState: AdapterState {
        convertToAdapterState(evmSyncState: eip20Kit.syncState)
    }

    var balanceStateUpdatedObservable: Observable<AdapterState> {
        eip20Kit.syncStateObservable.map { [weak self] in
            self?.convertToAdapterState(evmSyncState: $0) ?? .syncing(progress: nil, lastBlockDate: nil)
        }
    }
    
    var balanceData: BalanceData {
        let available = balanceDecimal(kitBalance: eip20Kit.balance, decimals: decimals)
        return BalanceData(balance: available, locked: lockedAmount)
    }

    var balanceDataUpdatedObservable: Observable<BalanceData> {
        Observable.merge(
            eip20Kit.balanceObservable.map { [weak self] in
                guard let self else {
                    return BalanceData(balance: 0)
                }
                let available = self.balanceDecimal(kitBalance: $0, decimals: self.decimals)
                return BalanceData(balance: available, locked: self.lockedAmount)
            },
            balanceDataSubject.asObservable()
        )
    }
}

extension Eip20Adapter: ISendEthereumAdapter {
    func transactionData(amount: BigUInt, address: EvmKit.Address) -> TransactionData {
        eip20Kit.transferTransactionData(to: address, value: amount)
    }
}

extension Eip20Adapter: IAllowanceAdapter {
    var pendingTransactions: [TransactionRecord] {
        eip20Kit.pendingTransactions().map { transactionConverter.transactionRecord(fromTransaction: $0) }
    }

    func allowance(spenderAddress: Address, defaultBlockParameter: BlockParameter) async throws -> Decimal {
        let address = try EvmKit.Address(hex: spenderAddress.raw)
        let allowanceString = try await eip20Kit.allowance(spenderAddress: address, defaultBlockParameter: .init(defaultBlockParameter))

        guard let significand = Decimal(string: allowanceString) else {
            return 0
        }

        return Decimal(sign: .plus, exponent: -decimals, significand: significand)
    }
}

extension Eip20Adapter: IApproveDataProvider {
    func approveSendData(token: Token, spenderAddress: Address, amount: BigUInt) throws -> SendData {
        let address = try EvmKit.Address(hex: spenderAddress.raw)
        let transactionData = eip20Kit.approveTransactionData(spenderAddress: address, amount: amount)

        return .evm(blockchainType: token.blockchainType, transactionData: transactionData)
    }
}

extension DefaultBlockParameter {
    init(_ blockParameter: BlockParameter) {
        switch blockParameter {
        case .pending: self = .pending
        case .latest: self = .latest
        case .earliest: self = .earliest
        case let .blockNumber(value): self = .blockNumber(value: value)
        }
    }
}
extension Eip20Adapter {

    func synceSrc20LockedRecord() {
        if let lockedService {
            lockedService.start()
            lockedAmountCancellable?.cancel()
            lockedAmountCancellable = lockedService.lockedAmountPublisher.sink { [weak self] lockedAmount in
                guard let self else { return }
                self.lockedAmount = self.balanceDecimal(kitBalance: lockedAmount, decimals: self.decimals)
                let available = self.balanceDecimal(kitBalance: self.eip20Kit.balance, decimals: self.decimals)
                self.balanceDataSubject.onNext(BalanceData(balance: available, locked: self.lockedAmount))
            }
        }else {
            let lockedRecordStorage = Core.shared.safe4CustomTokenStorage
            if let token = try? lockedRecordStorage.asset(address: contractAddress.eip55), let privateKey = evmKitWrapper.signer?.privateKey  {
                let service = SRC20Service(token: token, privateKey: privateKey, lockAddress: receiveAddress.address)
                let storage = Core.shared.safe4StorageManager.src20AllTokenLockedsRecordStorage
                let lockedService = SRC20LockedService(service: service, lockedRecordStorage: storage)
                self.lockedService = lockedService
                synceSrc20LockedRecord()
            }
        }
    }
}
