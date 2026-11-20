import UIKit

protocol IPresentDelegate: AnyObject {
    func present(viewController: UIViewController)
    func push(viewController: UIViewController)
}

extension IPresentDelegate {
    func push(viewController _: UIViewController) {
        // might be implemented by delegate
    }
}
