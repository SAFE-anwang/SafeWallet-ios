import Foundation
import UIKit
import BigInt
import ThemeKit

let superNodeRegisterSafeLockNum: Decimal = 5000
let superNodeRegisterCrowdFundingSafeLockNum: Decimal = 1000

let masterNodeRegisterSafeLockNum: Decimal = 1000
let masterNodeRegisterCrowdFundingSafeLockNum: Decimal = 200
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
            "safe_zone.safe4.node.tips.state.super".localized
        case .masterNode:
            "safe_zone.safe4.node.tips.state.master".localized
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

private var debounceIntervalKey: Void?
private var lastClickTimeKey: Void?

extension UIButton {
    
    private var debounceInterval: TimeInterval {
        get {
            return objc_getAssociatedObject(self, &debounceIntervalKey) as? TimeInterval ?? 0.5
        }
        set {
            objc_setAssociatedObject(self, &debounceIntervalKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var lastClickTime: TimeInterval {
        get {
            return objc_getAssociatedObject(self, &lastClickTimeKey) as? TimeInterval ?? 0
        }
        set {
            objc_setAssociatedObject(self, &lastClickTimeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func setDebounceInterval(_ interval: TimeInterval) {
        addTarget(self, action: #selector(debounceAction), for: .touchUpInside)
        self.debounceInterval = interval
    }

    @objc private func debounceAction() {
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastClickTime > debounceInterval {
            lastClickTime = currentTime
            sendActions(for: .touchUpInside)
        }
    }
}

extension UINavigationController {
    func popToViewController(ofClass: AnyClass, animated: Bool = true) {
        if let viewController = viewControllers.first(where: { $0.isKind(of: ofClass) }) {
            popToViewController(viewController, animated: animated)
        }
    }
}

extension UIColor {
    public static var themeDisabledGray: UIColor { color(dark: .themeGray, light: .themeLightGray) }
    public static var themeDisabledBgGray: UIColor { color(dark: .themeLightGray, light: .themeLight) }
}
