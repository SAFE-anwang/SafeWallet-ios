import Foundation
import UIKit
import BigInt

let superNodeRegisterSafeLockNum: Decimal = 5000
let masterNodeRegisterSafeLockNum: Decimal = 1000

let safe4Decimals: Int = 18

enum Safe4NodeType {
    case normal
    case superNode
    case masterNode
    
    var warnings: String {
        switch self {
        case .normal:
            ""
        case .superNode:
            "已经是超级节点".localized
        case .masterNode:
            "已经是主节点".localized
        }
    }
}

extension BigUInt {
    var safe4FomattedAmount: String {
        Decimal(bigUInt: self, decimals: safe4Decimals)?.safe4FormattedAmount ??  "-"
    }
}
extension Decimal {
    
    var safe4FormattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber)!
    }
}

extension UIView {
    func addEndEditingTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
                self.addGestureRecognizer(tapGesture)
    }
    
    @objc 
    private func dismissKeyboard() {
        self.endEditing(true)
    }
}

public extension BigUInt {
    func safe4ToDecimal() -> Decimal? {
        guard let decimalValue = Decimal(string: description) else {
            return nil
        }
        return decimalValue / pow(10, safe4Decimals)
    }
}
