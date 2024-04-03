import Foundation
import Hodler

struct TransactionLockInfo {
    let lockedUntil: Date
    let originalAddress: String
    let lockTimeInterval: HodlerPlugin.LockTimeInterval
    let unlockedHeight: Int?
    init(lockedUntil: Date, originalAddress: String, lockTimeInterval: HodlerPlugin.LockTimeInterval, unlockedHeight: Int?) {
        self.lockedUntil = lockedUntil
        self.originalAddress = originalAddress
        self.lockTimeInterval = lockTimeInterval
        self.unlockedHeight = unlockedHeight
    }
}
