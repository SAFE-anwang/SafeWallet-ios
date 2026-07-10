import SwiftUI
import UIKit

enum NftV2Module {
    @MainActor
    static func rootView(isPresented: Binding<Bool>) -> NftV2RootView {
        return NftV2RootView(
            viewModel: NftV2ViewModel(inventoryService: Core.shared.nftV2InventoryService),
            isPresented: isPresented
        )
    }

    static func legacyViewController() -> UIViewController {
        NftModule.viewController() ?? UIViewController()
    }
}

extension NftV2Module {
    @MainActor
    struct RootView: SwiftUI.View {
        @Binding var isPresented: Bool

        var body: some View {
            rootView(isPresented: $isPresented)
        }
    }
}
