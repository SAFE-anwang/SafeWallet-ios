import BigInt
import EvmKit
import Foundation
import Testing
@testable import WalletCore

struct LiquidityV3PositionCalldataTests {
    private static let mintSignature = "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))"
    private static let increaseLiquiditySignature = "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))"

    @Test func repairsMintWithMissingSignedTicksAndClearsMinimums() throws {
        let malformedInput = input(signature: Self.mintSignature, words: Array(0 ... 8).map { UInt8($0) })

        let corrected = try #require(
            LiquidityV3PositionCalldata.correctedInput(
                malformedInput,
                tickLower: BigInt(-7),
                tickUpper: BigInt(9)
            )
        )
        let correctedWords = Self.words(in: corrected)

        #expect(corrected.count == 4 + 11 * 32)
        #expect(correctedWords[0] == Self.word(0))
        #expect(correctedWords[1] == Self.word(1))
        #expect(correctedWords[2] == Self.word(2))
        #expect(correctedWords[3] == Data(repeating: 0xff, count: 31) + Data([0xf9]))
        #expect(correctedWords[4] == Data(repeating: 0, count: 31) + Data([0x09]))
        #expect(correctedWords[5] == Self.word(3))
        #expect(correctedWords[6] == Self.word(4))
        #expect(correctedWords[7] == Data(repeating: 0, count: 32))
        #expect(correctedWords[8] == Data(repeating: 0, count: 32))
        #expect(correctedWords[9] == Self.word(7))
        #expect(correctedWords[10] == Self.word(8))
    }

    @Test func clearsMintMinimumsWithoutChangingAlreadyCompleteTicks() throws {
        let completeInput = input(signature: Self.mintSignature, words: Array(0 ... 10).map { UInt8($0) })

        let corrected = try #require(
            LiquidityV3PositionCalldata.correctedInput(
                completeInput,
                tickLower: BigInt(-7),
                tickUpper: BigInt(9)
            )
        )
        let correctedWords = Self.words(in: corrected)

        #expect(corrected.count == completeInput.count)
        #expect(Array(correctedWords.prefix(7)) == Array(Self.words(in: completeInput).prefix(7)))
        #expect(correctedWords[7] == Data(repeating: 0, count: 32))
        #expect(correctedWords[8] == Data(repeating: 0, count: 32))
        #expect(correctedWords[9] == Self.word(9))
        #expect(correctedWords[10] == Self.word(10))
    }

    @Test func clearsIncreaseLiquidityMinimums() throws {
        let originalInput = input(signature: Self.increaseLiquiditySignature, words: Array(0 ... 5).map { UInt8($0) })

        let corrected = try #require(
            LiquidityV3PositionCalldata.correctedInput(
                originalInput,
                tickLower: BigInt(-7),
                tickUpper: BigInt(9)
            )
        )
        let correctedWords = Self.words(in: corrected)

        #expect(corrected.count == originalInput.count)
        #expect(correctedWords[0] == Self.word(0))
        #expect(correctedWords[1] == Self.word(1))
        #expect(correctedWords[2] == Self.word(2))
        #expect(correctedWords[3] == Data(repeating: 0, count: 32))
        #expect(correctedWords[4] == Data(repeating: 0, count: 32))
        #expect(correctedWords[5] == Self.word(5))
    }

    @Test func rejectsUnknownOrUnexpectedCalldata() {
        #expect(
            LiquidityV3PositionCalldata.correctedInput(
                Data([0x01, 0x02, 0x03, 0x04]),
                tickLower: BigInt(-7),
                tickUpper: BigInt(9)
            ) == nil
        )

        #expect(
            LiquidityV3PositionCalldata.correctedInput(
                input(signature: Self.mintSignature, words: [0, 1]),
                tickLower: BigInt(-7),
                tickUpper: BigInt(9)
            ) == nil
        )
    }

    private func input(signature: String, words: [UInt8]) -> Data {
        var input = ContractMethodHelper.methodId(signature: signature)
        for value in words {
            input.append(Self.word(value))
        }
        return input
    }

    private static func word(_ value: UInt8) -> Data {
        Data(repeating: value, count: 32)
    }

    private static func words(in input: Data) -> [Data] {
        (0 ..< (input.count - 4) / 32).map { index in
            Data(input[(4 + index * 32) ..< (4 + (index + 1) * 32)])
        }
    }
}
