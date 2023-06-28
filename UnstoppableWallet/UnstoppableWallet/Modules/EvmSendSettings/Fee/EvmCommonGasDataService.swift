import BigInt
import EvmKit
import MarketKit
import RxCocoa
import RxRelay
import RxSwift

class EvmCommonGasDataService {
    private let evmKit: EvmKit.Kit
    private let gasLimitSurchargePercent: Int

    private(set) var predefinedGasLimit: Int?
    
    private(set) var isEth2safe: Bool = false


    init(evmKit: EvmKit.Kit, gasLimit: Int? = nil, gasLimitSurchargePercent: Int = 0, isEth2safe: Bool = false) {
        self.evmKit = evmKit
        predefinedGasLimit = gasLimit
        self.gasLimitSurchargePercent = gasLimitSurchargePercent
        self.isEth2safe = isEth2safe
    }

    private func surchargedGasLimit(estimatedGasLimit: Int) -> Int {
        estimatedGasLimit + Int(Double(estimatedGasLimit) / 100.0 * Double(gasLimitSurchargePercent))
    }

    func gasDataSingle(gasPrice: GasPrice, transactionData: TransactionData, stubAmount: BigUInt? = nil) -> Single<EvmFeeModule.GasData> {
        if let gasLimit = predefinedGasLimit {
            return .just(EvmFeeModule.GasData(limit: gasLimit, price: gasPrice))
        }
        var adjustedTransactionData: TransactionData
        if isEth2safe {
            let _transactionData = TransactionData(to: evmKit.address, value: transactionData.value, input: transactionData.input)
            adjustedTransactionData = stubAmount.map { TransactionData(to: evmKit.address, value: $0, input: transactionData.input) } ?? _transactionData
        }else {
            adjustedTransactionData = stubAmount.map { TransactionData(to: transactionData.to, value: $0, input: transactionData.input) } ?? transactionData
        }

        return evmKit.estimateGas(transactionData: adjustedTransactionData, gasPrice: gasPrice).map { [weak self] estimatedGasLimit in
            let gasLimit = self?.surchargedGasLimit(estimatedGasLimit: estimatedGasLimit) ?? estimatedGasLimit
            if self?.isEth2safe == true {
                return EvmFeeModule.GasData(limit: 100000 , price: gasPrice)
            }
            return EvmFeeModule.GasData(limit: gasLimit, price: gasPrice)
        }
    }

}

extension EvmCommonGasDataService {
    static func instance(evmKit: EvmKit.Kit, blockchainType: BlockchainType, gasLimit: Int? = nil, gasLimitSurchargePercent: Int = 0, isEth2safe: Bool = false) -> EvmCommonGasDataService {
        guard let rollupFeeContractAddress = blockchainType.rollupFeeContractAddress else {
            return EvmCommonGasDataService(evmKit: evmKit, gasLimit: gasLimit, gasLimitSurchargePercent: gasLimitSurchargePercent, isEth2safe: isEth2safe)
        }

        return EvmRollupGasDataService(evmKit: evmKit, l1GasFeeContractAddress: rollupFeeContractAddress, gasLimitSurchargePercent: gasLimitSurchargePercent)
    }
}
