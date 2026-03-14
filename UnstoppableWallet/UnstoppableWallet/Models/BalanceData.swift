import Foundation

struct BalanceData: Hashable {
    let total: Decimal
    let available: Decimal
    let locked: Decimal // safe time locked

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
