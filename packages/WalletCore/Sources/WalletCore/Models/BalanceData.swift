import Foundation

public struct BalanceData: Hashable {
    public let total: Decimal
    public let available: Decimal
    public let locked: Decimal // safe time locked

    init(balance: Decimal, locked: Decimal = 0) {
        self.total = balance + locked
        self.available = balance
        self.locked = locked
    }

    init(total: Decimal, available: Decimal, locked: Decimal = 0) {
        self.total = total
        self.available = available
        self.locked = locked
    }
}
