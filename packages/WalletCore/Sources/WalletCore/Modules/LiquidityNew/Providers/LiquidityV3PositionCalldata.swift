import BigInt
import EvmKit
import Foundation

enum LiquidityV3PositionCalldata {
    private static let mintSignature = "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))"
    private static let increaseLiquiditySignature = "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))"
    private static let selectorSize = 4
    private static let wordSize = 32

    /// Repairs the calldata emitted by UniswapKit 3.2.2 for new positions and clears
    /// swap-style minimums which are not valid constraints for a position mint.
    static func correctedInput(_ input: Data, tickLower: BigInt, tickUpper: BigInt) -> Data? {
        guard input.count >= selectorSize else {
            return nil
        }

        let selector = Data(input.prefix(selectorSize))
        let mintSelector = ContractMethodHelper.methodId(signature: mintSignature)
        let increaseLiquiditySelector = ContractMethodHelper.methodId(signature: increaseLiquiditySignature)

        var corrected = input

        if selector == mintSelector {
            let truncatedMintSize = selectorSize + 9 * wordSize
            let completeMintSize = selectorSize + 11 * wordSize

            if input.count == truncatedMintSize {
                guard let lowerTickWord = signedTickWord(tickLower),
                      let upperTickWord = signedTickWord(tickUpper)
                else {
                    return nil
                }

                let endOfFeeWord = selectorSize + 3 * wordSize
                corrected = Data(input.prefix(endOfFeeWord))
                corrected.append(lowerTickWord)
                corrected.append(upperTickWord)
                corrected.append(input[endOfFeeWord...])
            } else if input.count != completeMintSize {
                return nil
            }

            zeroWord(in: &corrected, index: 7)
            zeroWord(in: &corrected, index: 8)
            return corrected
        }

        if selector == increaseLiquiditySelector {
            guard input.count == selectorSize + 6 * wordSize else {
                return nil
            }

            zeroWord(in: &corrected, index: 3)
            zeroWord(in: &corrected, index: 4)
            return corrected
        }

        return nil
    }

    private static func signedTickWord(_ tick: BigInt) -> Data? {
        guard let value = Int64(tick.description), (-8_388_608 ... 8_388_607).contains(value) else {
            return nil
        }

        var encodedValue = tick.magnitude
        if value < 0 {
            encodedValue = BigUInt(2).power(256) - encodedValue
        }

        let serialized = encodedValue.serialize()
        guard serialized.count <= wordSize else {
            return nil
        }

        return Data(repeating: 0, count: wordSize - serialized.count) + serialized
    }

    private static func zeroWord(in data: inout Data, index: Int) {
        let start = selectorSize + index * wordSize
        data.replaceSubrange(start ..< start + wordSize, with: Data(repeating: 0, count: wordSize))
    }
}
