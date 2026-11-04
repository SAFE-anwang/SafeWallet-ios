import Testing
@testable import WalletCore

struct LiquidityV3TickRangeTests {
    @Test func pancakeMediumFeeUsesAlignedFullRangeBounds() {
        let bounds = LiquidityV3TickRange.usableFullRangeBounds(
            minTick: -887_272,
            maxTick: 887_272,
            tickSpacing: 50
        )

        #expect(bounds?.lower == -887_250)
        #expect(bounds?.upper == 887_250)
        #expect(bounds.map { LiquidityV3TickRange.isAligned($0.lower, tickSpacing: 50) } == true)
        #expect(bounds.map { LiquidityV3TickRange.isAligned($0.upper, tickSpacing: 50) } == true)
    }

    @Test func unitSpacingKeepsGlobalBounds() {
        let bounds = LiquidityV3TickRange.usableFullRangeBounds(
            minTick: -887_272,
            maxTick: 887_272,
            tickSpacing: 1
        )

        #expect(bounds?.lower == -887_272)
        #expect(bounds?.upper == 887_272)
    }

    @Test func invalidSpacingDoesNotProduceBounds() {
        #expect(
            LiquidityV3TickRange.usableFullRangeBounds(
                minTick: -887_272,
                maxTick: 887_272,
                tickSpacing: 0
            ) == nil
        )
    }
}
