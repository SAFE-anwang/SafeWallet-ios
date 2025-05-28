import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import ComponentKit
import HUD

struct RewardsView: View {
    
    @StateObject var viewModel: RewardsViewModel
    @Environment(\.presentationMode) private var presentationMode

    init(viewModel: RewardsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            switch viewModel.state {
            case .loading:
                ProgressView()
                
            case let .completed(items):
                if items.isEmpty {
                    PlaceholderViewNew(image: Image("safe4_empty"), text: "safe_zone.safe4.empty.description".localized)
                }else {
                    BottomGradientWrapper {
                        ListSection {
                            ClickableRow(action: {}) {
                                Text("tx_info.date".localized)
                                    .themeSubhead1(alignment: .leading)
                                Spacer()
                                Text("send.amount_placeholder".localized)
                                    .themeSubhead1(alignment: .trailing)
                            }

                            ForEach(items, id: \.date) { item in
                                ClickableRow(action: {}) {
                                    Text(item.date)
                                        .themeSubhead1(color: item.withdrawEnabled ? .blue : .themeLeah, alignment: .leading)

                                    Spacer()
                                    Text(item.amountStr)
                                        .themeSubhead1(color: item.withdrawEnabled ? .blue : .themeLeah, alignment: .trailing)
                                }
                            }
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                            
                    } bottomContent: {
                        Button(action: {
                            
                            viewModel.onSuccess = { sendState in
                                switch sendState {
                                case .normal, .loading:()
                                case .completed:
                                    DispatchQueue.main.async {
                                        HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                    
                                case .failed(_):
                                    HudHelper.instance.show(banner: .error(string: "transactions.failed".localized))
                                }
                            }
                            viewModel.withdraw()
                            
                        }) {
                            HStack {
                                if case .loading = viewModel.sendState {
                                    ProgressView()
                                }
                                Text("safe_zone.safe4.withdraw".localized)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(style: .yellow))
                        .disabled(!viewModel.withdrawEnabled)
                    }
                }
                
            case .failed(_):
                SyncErrorView {
                    viewModel.refresh()
                }
            }
        }
        .navigationBarTitle("safe_zone.row.rewards".localized + "safe_zone.safe4.withdraw".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
