import UIKit
import ThemeKit
import RxSwift
import StorageKit
import LanguageKit

struct MainSafeZoneModule {

    static func viewController() -> UIViewController {
        
        let viewModel = MainSafeZoneViewModel()

        return MainSafeZoneViewController(viewModel: viewModel, urlManager: UrlManager(inApp: true))
    }

}
