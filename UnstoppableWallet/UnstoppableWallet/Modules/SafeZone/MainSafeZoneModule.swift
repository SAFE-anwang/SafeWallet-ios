import UIKit
import ThemeKit
import RxSwift
import SwiftUI

struct MainSafeZoneModule {
    static func view() -> some View {
        return MainSafeZoneView()
    }
    
    static func viewController() -> UIViewController {
        return MainSafeZoneView().toViewController()
    }
    
    static func navigationController() -> UIViewController {
        let navController = ThemeNavigationController(rootViewController: UIViewController())
        navController.viewControllers.removeAll()
        let contentView = MainSafeZoneView()
            .environment(\.navigationController, navController)
    
        let hostingController = UIHostingController(rootView: contentView)
        navController.viewControllers = [hostingController]
        navController.tabBarItem = UITabBarItem(title: "safe_zone.nav.title".localized, image: UIImage(named: "filled_settings_2_24"), tag: 0)
        return navController
    }
}

struct NavigationControllerKey: EnvironmentKey {
    static let defaultValue: UINavigationController? = nil
}

extension EnvironmentValues {
    var navigationController: UINavigationController? {
        get { self[NavigationControllerKey.self] }
        set { self[NavigationControllerKey.self] = newValue }
    }
}
