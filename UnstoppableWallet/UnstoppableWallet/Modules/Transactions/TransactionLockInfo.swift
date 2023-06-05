import Foundation
import Hodler

struct TransactionLockInfo {
    let lockedUntil: Date
    let originalAddress: String
    let unlockedHeight: Int?
    
    init(lockedUntil: Date, originalAddress: String, unlockedHeight: Int?) {
        self.lockedUntil = lockedUntil
        self.originalAddress = originalAddress
        self.unlockedHeight = unlockedHeight
    }

}
