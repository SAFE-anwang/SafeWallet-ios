import UIKit

struct FallbackBlockModule {
    
    static func viewController(image: BottomSheetTitleView.Image? = nil, title: String, subtitle: String? = nil, viewItems: [SelectorModule.ViewItem], onSelect: @escaping (Int) -> ()) -> UIViewController {
        let viewController = FallbackBlockViewController(image: image, title: title, subtitle: subtitle, viewItems: viewItems, onSelect: onSelect)
        return viewController.toBottomSheet
    }

}
