import BigInt
import EvmKit

struct LiquidityFeeStep {
    let id: String
    let transactionData: TransactionData
    let gasLimit: Int
    let surchargedGasLimit: Int
    let l1Fee: BigUInt?
    let gasPrice: GasPrice
    let isFallbackEstimate: Bool

    var totalFee: BigUInt {
        BigUInt(surchargedGasLimit * gasPrice.max) + (l1Fee ?? 0)
    }
}

struct LiquidityFeePlan {
    let steps: [LiquidityFeeStep]

    var gasLimit: Int {
        steps.reduce(0) { $0 + $1.gasLimit }
    }

    var surchargedGasLimit: Int {
        steps.reduce(0) { $0 + $1.surchargedGasLimit }
    }

    var l1Fee: BigUInt? {
        let value = steps.reduce(BigUInt(0)) { $0 + ($1.l1Fee ?? 0) }
        return value == 0 ? nil : value
    }

    var hasFallbackEstimate: Bool {
        steps.contains(where: { $0.isFallbackEstimate })
    }

    var aggregateFeeData: EvmFeeData {
        EvmFeeData(gasLimit: gasLimit, surchargedGasLimit: surchargedGasLimit, l1Fee: l1Fee)
    }

    func step(id: String) -> LiquidityFeeStep? {
        steps.first(where: { $0.id == id })
    }
}
