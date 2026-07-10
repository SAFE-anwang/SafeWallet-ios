import SwiftUI
import UIKit

struct NftV2LegacyWrapperView: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context _: Context) -> UIViewController {
        if controller is UINavigationController {
            return controller
        }

        return ThemeNavigationController(rootViewController: controller)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
