import SwiftUI

enum NftV2Module {
    @MainActor
    struct RootView: SwiftUI.View {
        @Binding var isPresented: Bool
        @StateObject private var viewModel: NftV2ViewModel

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
            _viewModel = StateObject(wrappedValue: NftV2ViewModel(inventoryService: Core.shared.nftV2InventoryService))
        }

        var body: some View {
            NftV2RootView(viewModel: viewModel, isPresented: $isPresented)
        }
    }
}
