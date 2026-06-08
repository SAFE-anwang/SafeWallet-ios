import BigInt
import Combine
import EvmKit
import Foundation
import MarketKit
import OneInchKit
import RxCocoa
import RxSwift
import UniswapKit
import web3swift
import Combine

protocol ISendEvmTransactionService {
    var state: SendEvmTransactionService.State { get }
    var stateObservable: Observable<SendEvmTransactionService.State> { get }

    var dataState: SendEvmTransactionService.DataState { get }

    var sendState: SendEvmTransactionService.SendState { get }
    var sendStateObservable: Observable<SendEvmTransactionService.SendState> { get }

    var ownAddress: EvmKit.Address { get }

    func methodName(input: Data) -> String?
    func send()
}

class SendEvmTransactionService {
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()

    private let sendData: SendEvmData
    private let privateSendMode: PrivateSendMode
    private let evmKitWrapper: EvmKitWrapper
    private let settingsService: EvmSendSettingsService
    private let evmLabelManager: EvmLabelManager

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notReady(errors: [], warnings: []) {
        didSet {
            stateRelay.accept(state)
        }
    }

    private(set) var dataState: DataState

    private let sendStateRelay = PublishRelay<SendState>()
    private(set) var sendState: SendState = .idle {
        didSet {
            sendStateRelay.accept(sendState)
        }
    }

    init(sendData: SendEvmData, privateSendMode: SendEvmTransactionService.PrivateSendMode, evmKitWrapper: EvmKitWrapper, settingsService: EvmSendSettingsService, evmLabelManager: EvmLabelManager) {
        self.sendData = sendData
        self.privateSendMode = privateSendMode
        self.evmKitWrapper = evmKitWrapper
        self.settingsService = settingsService
        self.evmLabelManager = evmLabelManager

        dataState = DataState(
            transactionData: sendData.transactionData,
            additionalInfo: sendData.additionalInfo,
            decoration: evmKitWrapper.evmKit.decorate(transactionData: sendData.transactionData),
            nonce: settingsService.nonceService.frozen ? settingsService.nonceService.nonce : nil
        )

        subscribe(disposeBag, settingsService.statusObservable) { [weak self] in self?.sync(status: $0) }
    }

    private var evmKit: EvmKit.Kit {
        evmKitWrapper.evmKit
    }

    private var evmBalance: BigUInt {
        evmKit.accountState?.balance ?? 0
    }

    private func sync(status: DataStatus<FallibleData<EvmSendSettingsService.Transaction>>) {
        switch status {
        case .loading:
            state = .notReady(errors: [], warnings: [])
        case let .failed(error):
            syncDataState()
            state = .notReady(errors: [error], warnings: [])
        case let .completed(fallibleTransaction):
            syncDataState(transaction: fallibleTransaction.data)

            let warnings = sendData.warnings + fallibleTransaction.warnings
            let errors = sendData.errors + fallibleTransaction.errors
            if errors.isEmpty {
                state = .ready(warnings: warnings)
            } else {
                state = .notReady(errors: errors, warnings: warnings)
            }
        }
    }

    private func syncDataState(transaction: EvmSendSettingsService.Transaction? = nil) {
        let transactionData = transaction?.transactionData ?? sendData.transactionData

        dataState = DataState(
            transactionData: transactionData,
            additionalInfo: sendData.additionalInfo,
            decoration: evmKit.decorate(transactionData: transactionData),
            nonce: settingsService.nonceService.frozen ? settingsService.nonceService.nonce : nil
        )
    }
}

extension SendEvmTransactionService: ISendEvmTransactionService {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var sendStateObservable: Observable<SendState> {
        sendStateRelay.asObservable()
    }

    var ownAddress: EvmKit.Address {
        evmKit.receiveAddress
    }

    var blockchainType: BlockchainType {
        evmKitWrapper.blockchainType
    }

    func methodName(input: Data) -> String? {
        evmLabelManager.methodLabel(input: input)
    }

    func send() {
        guard case .ready = state, case let .completed(fallibleTransaction) = settingsService.status else {
            let error = TransactionError.notReady
            print("[SendEvmTransaction] ERROR: Transaction not ready, state=\(state)")
            sendState = .failed(error: error)
            return
        }
        let transaction = fallibleTransaction.data

        // Log transaction details for debugging
        print("[SendEvmTransaction] Sending transaction:")
        print("  - to: \(transaction.transactionData.to.eip55)")
        print("  - value: \(transaction.transactionData.value)")
        print("  - gasLimit: \(transaction.gasData.limit)")
        print("  - gasPrice: \(transaction.gasData.price)")
        print("  - nonce: \(transaction.nonce ?? -1)")

        sendState = .sending
        switch privateSendMode {
        case .none, .protected:
            if transaction.transactionData.times != -1 {
                guard let value = (transaction.transactionData.value / BigUInt(transaction.transactionData.times)).safe4ToDecimal(),
                      let type = web3swift.AccountManager.ContractType.contractType(value: value) else {
                    sendState = .failed(error: TransactionError.invalidParameters)
                    return
                }
                
                evmKitWrapper.sendSafe4LineLockSingle(type: type, transactionData: transaction.transactionData)
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe(onSuccess: { [weak self] hashStr in
                        self?.sendState = .sent(transactionHash: hashStr.hs.data)
                    }, onError: { [weak self] error in
                        let categorizedError = self?.categorizeError(error) ?? error
                        self?.sendState = .failed(error: categorizedError)
                    })
                    .disposed(by: disposeBag)
            }else {
                evmKitWrapper.sendSingle(
                    transactionData: transaction.transactionData,
                    gasPrice: transaction.gasData.price,
                    gasLimit: transaction.gasData.limit,
                    privateSend: privateSendMode.privateSend,
                    nonce: transaction.nonce
                )
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onSuccess: { [weak self] fullTransaction in
                    let txHash = fullTransaction.transaction.hash.hs.hexString
                    print("[SendEvmTransaction] SUCCESS: Transaction sent, hash=\(txHash)")
                    self?.sendState = .sent(transactionHash: fullTransaction.transaction.hash)
                }, onError: { [weak self] error in
                    print("[SendEvmTransaction] ERROR: Transaction failed: \(error.localizedDescription)")
                    print("  - underlying error: \(error)")
                    let categorizedError = self?.categorizeError(error) ?? error
                    self?.sendState = .failed(error: categorizedError)
                })
                .disposed(by: disposeBag)
                
            }
        case let .cancelPrevious(hash):
            Task { [weak self] in
                do {
                    let successful = try await self?.evmKitWrapper.sendCancel(hash: hash)
                    if successful ?? false {
                        print("[SendEvmTransaction] SUCCESS: Cancel transaction sent")
                        self?.sendState = .sent(transactionHash: hash)
                    } else {
                        print("[SendEvmTransaction] ERROR: Cancel transaction failed")
                        self?.sendState = .failed(error: SendEvmTransactionService.TransactionError.unexpectedError)
                    }
                } catch {
                    print("[SendEvmTransaction] ERROR: Cancel transaction exception: \(error.localizedDescription)")
                    let categorizedError = self?.categorizeError(error) ?? error
                    self?.sendState = .failed(error: categorizedError)
                }
            }
        }
    }
    
    // MARK: - Error Categorization
    
    private func categorizeError(_ error: Error) -> Error {
        let errorDescription = error.localizedDescription.lowercased()

        if case let AppError.ethereum(reason) = error.convertedError,
           case .invalidNftAsset = reason
        {
            print("[SendEvmTransaction] Categorized as: invalidNftAsset")
            return error.convertedError
        }
        
        // Gas-related errors
        if errorDescription.contains("insufficient funds") || 
           errorDescription.contains("gas") ||
           errorDescription.contains("out of gas") {
            print("[SendEvmTransaction] Categorized as: insufficientBalance")
            return TransactionError.insufficientBalance(requiredBalance: 0)
        }
        
        // Nonce errors
        if errorDescription.contains("nonce") || 
           errorDescription.contains("replacement transaction") {
            print("[SendEvmTransaction] Categorized as: nonceError")
            return TransactionError.nonceError
        }
        
        // Network errors
        if errorDescription.contains("network") || 
           errorDescription.contains("timeout") ||
           errorDescription.contains("connection") {
            print("[SendEvmTransaction] Categorized as: networkError")
            return TransactionError.networkError
        }
        
        // Contract execution errors
        if errorDescription.contains("revert") || 
           errorDescription.contains("execution failed") {
            print("[SendEvmTransaction] Categorized as: contractError")
            return TransactionError.contractError(reason: error.localizedDescription)
        }
        
        print("[SendEvmTransaction] Error not categorized, returning original")
        return error
    }
}

extension SendEvmTransactionService {
    enum PrivateSendMode {
        case none
        case protected
        case cancelPrevious(Data)

        var privateSend: Bool {
            switch self {
            case .none: return false
            default: return true
            }
        }
    }

    enum State {
        case ready(warnings: [Warning])
        case notReady(errors: [Error], warnings: [Warning])
    }

    struct DataState {
        let transactionData: TransactionData?
        let additionalInfo: SendEvmData.AdditionInfo?
        var decoration: TransactionDecoration?
        let nonce: Int?
//        let lockTime: Int?
    }

    enum SendState {
        case idle
        case sending
        case sent(transactionHash: Data)
        case failed(error: Error)
    }

    enum TransactionError: Error {
        case unexpectedError
        case noTransactionData
        case insufficientBalance(requiredBalance: BigUInt)
        case notReady
        case invalidParameters
        case nonceError
        case networkError
        case contractError(reason: String)
    }
}
