import UIKit
import SwiftUI

enum NftModule {
    static func viewController() -> UIViewController? {
        let coinPriceService = WalletCoinPriceService()

        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }

        let service = NftService(
            account: account,
            nftAdapterManager: Core.shared.nftAdapterManager,
            nftMetadataManager: Core.shared.nftMetadataManager,
            nftMetadataSyncer: Core.shared.nftMetadataSyncer,
            balanceHiddenManager: Core.shared.balanceHiddenManager,
            balanceConversionManager: Core.shared.balanceConversionManager,
            coinPriceService: coinPriceService
        )

        coinPriceService.delegate = service

        let viewModel = NftViewModel(service: service)
        let headerViewModel = NftHeaderViewModel(service: service)

        return NftViewController(viewModel: viewModel, headerViewModel: headerViewModel)
    }
}

extension NftModule {
    struct View: UIViewControllerRepresentable {
        typealias UIViewControllerType = UIViewController

        func makeUIViewController(context _: Context) -> UIViewController {
            ThemeNavigationController(rootViewController: NftModule.viewController() ?? UIViewController())
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<View>) {}
    }
}
