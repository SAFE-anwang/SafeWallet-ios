import SwiftUI

struct AppearanceModule {
    static func view() -> some View {
        let viewModel = AppearanceViewModel()
        return AppearanceView(viewModel: viewModel)
    }
}
