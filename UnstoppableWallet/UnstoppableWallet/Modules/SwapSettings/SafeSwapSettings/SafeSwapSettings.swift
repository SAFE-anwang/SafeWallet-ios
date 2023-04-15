
import Foundation
import SafeSwapKit
import EvmKit

struct SafeSwapSettings {
    var allowedSlippage: Decimal
    var recipient: Address?

    init(allowedSlippage: Decimal = 1, recipient: Address? = nil) {
        self.allowedSlippage = allowedSlippage
        self.recipient = recipient
    }

}
