import BigInt
import EvmKit
import MarketKit
import RxCocoa
import RxRelay
import RxSwift

class EvmCommonGasDataService {
    private let evmKit: EvmKit.Kit
    private(set) var predefinedGasLimit: Int?
    private(set) var gasLimitType: GasLimitType = .common
    
    init(evmKit: EvmKit.Kit, predefinedGasLimit: Int?, gasLimitType: GasLimitType = .common) {
        self.evmKit = evmKit
        self.predefinedGasLimit = predefinedGasLimit
        self.gasLimitType = gasLimitType
    }

    func gasDataSingle(gasPrice: GasPrice, transactionData: TransactionData, stubAmount: BigUInt? = nil) -> Single<EvmFeeModule.GasData> {
        if let predefinedGasLimit {
            return .just(EvmFeeModule.GasData(limit: predefinedGasLimit, price: gasPrice))
        }

        let surchargeRequired = !transactionData.input.isEmpty
        
        var adjustedTransactionData: TransactionData
        
        switch gasLimitType {
        case .common:
            adjustedTransactionData = stubAmount.map { TransactionData(to: transactionData.to, value: $0, input: transactionData.input) } ?? transactionData
        case .contract:
            let _transactionData = TransactionData(to: evmKit.address, value: transactionData.value, input: transactionData.input)
            adjustedTransactionData = stubAmount.map { TransactionData(to: evmKit.address, value: $0, input: transactionData.input) } ?? _transactionData
        }
        
        return evmKit.estimateGas(transactionData: adjustedTransactionData, gasPrice: gasPrice)
                .map { estimatedGasLimit in
                    
                    let limit = surchargeRequired ? EvmFeeModule.surcharged(gasLimit: estimatedGasLimit) : estimatedGasLimit
                    return EvmFeeModule.GasData(
                            limit: limit,
                            estimatedLimit: estimatedGasLimit,
                            price: gasPrice
                    )
                }
    }
}



extension EvmCommonGasDataService {

    static func instance(evmKit: EvmKit.Kit, blockchainType: BlockchainType, predefinedGasLimit: Int?, gasLimitType: GasLimitType = .common) -> EvmCommonGasDataService {
        if let rollupFeeContractAddress = blockchainType.rollupFeeContractAddress {
            return EvmRollupGasDataService(evmKit: evmKit, l1GasFeeContractAddress: rollupFeeContractAddress, predefinedGasLimit: predefinedGasLimit)
        }

        return EvmCommonGasDataService(evmKit: evmKit, predefinedGasLimit: predefinedGasLimit, gasLimitType: gasLimitType)
    }

}

enum GasLimitType {
    case common
    case contract
}
