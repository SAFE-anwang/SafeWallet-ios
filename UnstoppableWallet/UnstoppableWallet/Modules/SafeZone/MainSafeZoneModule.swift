import UIKit
import ThemeKit
import RxSwift

struct MainSafeZoneModule {

    static func viewController() -> UIViewController {
        
        let viewModel = MainSafeZoneViewModel()

        return MainSafeZoneViewController(viewModel: viewModel, urlManager: UrlManager(inApp: true))
    }

}
