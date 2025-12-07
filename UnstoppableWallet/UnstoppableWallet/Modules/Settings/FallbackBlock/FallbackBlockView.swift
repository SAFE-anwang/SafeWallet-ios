import SwiftUI

struct FallbackBlockView: View {
    @StateObject private var viewModel: FallbackBlockViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var mainViewModel: MainViewModel
    
    init() {
        let viewModel = FallbackBlockViewModel(walletManager: Core.shared.walletManager,
                                               accountManager: Core.shared.accountManager,
                                               adapterManager: Core.shared.adapterManager
        )
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            VStack(spacing: .margin16) {
                HStack {
                    Text("safe_setting.fallback.title".localized)
                        .themeBody()
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image("close_3_24")
                    }
                }
                    
                ScrollableThemeView {
                    VStack(spacing: .margin32) {
                        ListSection {
                            ForEach(viewModel.fallbackBlockViewItems) { item in
                                ClickableRow {
                                    viewModel.fallbackBlock(item: item)
                                    dismiss()
                                    mainViewModel.selectedTab = .wallet
                                } content: {
                                    Text("\(item.item.title)").themeBody(color: .themeGray)
                                    if item.item.selected {
                                        Image("check_1_20").themeIcon(color: .themeRemus)
                                    }
                                }
                            }
                        }
                    }
                }
            }.padding(EdgeInsets(top: .margin16, leading: .margin16, bottom: .margin16, trailing: .margin16))
        }
    }
}
