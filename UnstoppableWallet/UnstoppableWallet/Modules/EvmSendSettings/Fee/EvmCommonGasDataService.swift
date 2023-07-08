import BigInt
import EvmKit
import MarketKit
import RxCocoa
import RxRelay
import RxSwift

class EvmCommonGasDataService {
    private let evmKit: EvmKit.Kit
    private(set) var predefinedGasLimit: Int?
    private(set) var isEth2safe: Bool = false

    init(evmKit: EvmKit.Kit, predefinedGasLimit: Int?, isEth2safe: Bool = false) {
        self.evmKit = evmKit
        self.predefinedGasLimit = predefinedGasLimit
        self.isEth2safe = isEth2safe
    }

    func gasDataSingle(gasPrice: GasPrice, transactionData: TransactionData, stubAmount: BigUInt? = nil) -> Single<EvmFeeModule.GasData> {
        if let predefinedGasLimit {
            return .just(EvmFeeModule.GasData(limit: predefinedGasLimit, price: gasPrice))
        }

        let surchargeRequired = !transactionData.input.isEmpty
        
        var adjustedTransactionData: TransactionData
        if isEth2safe {
            let _transactionData = TransactionData(to: evmKit.address, value: transactionData.value, input: transactionData.input)
            adjustedTransactionData = stubAmount.map { TransactionData(to: evmKit.address, value: $0, input: transactionData.input) } ?? _transactionData
        }else {
            adjustedTransactionData = stubAmount.map { TransactionData(to: transactionData.to, value: $0, input: transactionData.input) } ?? transactionData
        }

        return evmKit.estimateGas(transactionData: adjustedTransactionData, gasPrice: gasPrice)
                .map { estimatedGasLimit in
                    let limit = surchargeRequired ? EvmFeeModule.surcharged(gasLimit: estimatedGasLimit) : estimatedGasLimit
                    
                    return EvmFeeModule.GasData(
                        limit: self.isEth2safe == true ? 100000 : limit,
                            estimatedLimit: estimatedGasLimit,
                            price: gasPrice
                    )
                }
    }

}

extension EvmCommonGasDataService {

    static func instance(evmKit: EvmKit.Kit, blockchainType: BlockchainType, predefinedGasLimit: Int?, isEth2safe: Bool = false) -> EvmCommonGasDataService {
        if let rollupFeeContractAddress = blockchainType.rollupFeeContractAddress {
            return EvmRollupGasDataService(evmKit: evmKit, l1GasFeeContractAddress: rollupFeeContractAddress, predefinedGasLimit: predefinedGasLimit)
        }

        return EvmCommonGasDataService(evmKit: evmKit, predefinedGasLimit: predefinedGasLimit, isEth2safe: isEth2safe)
    }

}
