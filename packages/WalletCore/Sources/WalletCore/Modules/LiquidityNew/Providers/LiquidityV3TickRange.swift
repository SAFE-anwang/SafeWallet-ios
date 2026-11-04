enum LiquidityV3TickRange {
    static func usableFullRangeBounds(minTick: Int, maxTick: Int, tickSpacing: Int) -> (lower: Int, upper: Int)? {
        guard tickSpacing > 0, minTick < 0, maxTick > 0, minTick < maxTick else {
            return nil
        }

        // Integer division truncates toward zero: this rounds the negative minimum up
        // and the positive maximum down to the nearest usable tick boundaries.
        let lower = minTick / tickSpacing * tickSpacing
        let upper = maxTick / tickSpacing * tickSpacing

        guard lower >= minTick, upper <= maxTick, lower < upper else {
            return nil
        }

        return (lower, upper)
    }

    static func isAligned(_ tick: Int, tickSpacing: Int) -> Bool {
        tickSpacing > 0 && tick % tickSpacing == 0
    }
}
