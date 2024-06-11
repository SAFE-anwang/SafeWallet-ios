import BigInt
import Foundation
import EvmKit
import MarketKit
import RxRelay
import RxSwift

class LiquidityFeeService {
    let gasPriceService: IGasPriceService
    let coinService: CoinService

    private let evmKit: EvmKit.Kit
    private var predefinedGasLimit: Int?
    private var transactionData: TransactionData

    private let transactionStatusRelay = PublishRelay<DataStatus<FallibleData<EvmFeeModule.Transaction>>>()
    private(set) var status: DataStatus<FallibleData<EvmFeeModule.Transaction>> = .loading {
        didSet {
            transactionStatusRelay.accept(status)
        }
    }

    private var disposeBag = DisposeBag()
    private var gasPriceDisposeBag = DisposeBag()
    
    init(evmKit: EvmKit.Kit, gasPriceService: IGasPriceService, coinService: CoinService, transactionData: TransactionData, predefinedGasLimit: Int? = nil) {
        self.evmKit = evmKit
        self.gasPriceService = gasPriceService
        self.coinService = coinService
        self.transactionData = transactionData
        self.predefinedGasLimit = predefinedGasLimit
        
        sync(gasPriceStatus: gasPriceService.status)
        subscribe(gasPriceDisposeBag, gasPriceService.statusObservable) { [weak self] in
            self?.sync(gasPriceStatus: $0)
        }
    }

    private func sync(gasPriceStatus: DataStatus<FallibleData<EvmFeeModule.GasPrices>>) {
        switch gasPriceStatus {
        case .loading: status = .loading
        case let .failed(error): status = .failed(error)
        case let .completed(fallibleGasPrices): sync(fallibleGasPrices: fallibleGasPrices)
        }
    }

    private func sync(fallibleGasPrices: FallibleData<EvmFeeModule.GasPrices>) {

        Task {               
            let single: Single<EvmFeeModule.Transaction>
            let transactionData = transactionData
            let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKit)
            let gasPrice = try await gasPriceProvider.gasPrice()
            
            do {
                let gasLimit: Int
                if let predefinedGasLimit {
                    gasLimit = predefinedGasLimit
                }else {
                    gasLimit = try await evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
                }
               
                let adjustedGasData = EvmFeeModule.GasData(limit: gasLimit, price: gasPrice)
                
                if transactionData.input.isEmpty, transactionData.value == evmBalance {
                    adjustedGasData.set(price: fallibleGasPrices.data.userDefined)
                    
                    if transactionData.value <= adjustedGasData.fee {
                        single = Single.error(EvmFeeModule.GasDataError.insufficientBalance)
                    } else {
                        let adjustedTransactionData = TransactionData(to: transactionData.to, value: transactionData.value - adjustedGasData.fee, input: transactionData.input)
                        single = Single.just(EvmFeeModule.Transaction(transactionData: adjustedTransactionData, gasData: adjustedGasData))
                    }
                    
                }else {
                    adjustedGasData.set(price: fallibleGasPrices.data.userDefined)
                    let adjustedTransactionData = EvmFeeModule.Transaction(transactionData: transactionData, gasData: adjustedGasData)
                    single = Single.just(adjustedTransactionData)
                }
            }catch{
                single = Single.error(EvmFeeModule.GasDataError.insufficientBalance)
            }
            
            single.subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe(onSuccess: { [weak self] transaction in
                        self?.syncStatus(transaction: transaction, errors: fallibleGasPrices.errors, warnings: fallibleGasPrices.warnings)
                    }, onError: { error in
                        self.status = .failed(error)
                    })
                    .disposed(by: disposeBag)
        }
    }
    
    private var evmBalance: BigUInt {
        evmKit.accountState?.balance ?? 0
    }

    private func syncStatus(transaction: EvmFeeModule.Transaction, errors: [Error], warnings: [Warning]) {
        var errors: [Error] = errors
/* // remove limit
        let totalAmount = transaction.gasData.fee
        if totalAmount > evmBalance {
            errors.append(SendEvmTransactionService.TransactionError.insufficientBalance(requiredBalance: totalAmount))
        }
 */
        let transactionData = TransactionData(to: transaction.transactionData.to, value: 0, input: transaction.transactionData.input)
        let newTransaction = EvmFeeModule.Transaction(transactionData: transactionData, gasData: transaction.gasData)
        
        status = .completed(FallibleData<EvmFeeModule.Transaction>(
            data: newTransaction, errors: errors, warnings: warnings
        ))
    }
    
}

extension LiquidityFeeService: IEvmFeeService {
    
    var statusObservable: Observable<DataStatus<FallibleData<EvmFeeModule.Transaction>>> {
        transactionStatusRelay.asObservable()
    }
}

