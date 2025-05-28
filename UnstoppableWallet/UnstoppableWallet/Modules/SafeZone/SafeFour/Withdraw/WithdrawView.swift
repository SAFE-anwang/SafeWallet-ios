import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import ComponentKit
import HUD

struct WithdrawView: View {
    @StateObject var viewModel: WithdrawViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    init(viewModel: WithdrawViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            switch viewModel.dataState {
            case .loading:
                ProgressView()
                
            case let .completed(items):
                
                if items.isEmpty {
                    PlaceholderViewNew(image: Image("no_data_48"), text: "coin_markets.empty".localized)
                }else {
                    BottomGradientWrapper {
                        VStack(spacing: .margin32) {
                            ListSection {
                                ForEach(items, id: \.id) { item in
                                    ClickableRow(action: {
                                        if item.isEnable {
                                            viewModel.choose(item: item)
                                        }else {
                                            HudHelper.instance.show(banner: .error(string: "safe_withdraw.votelocked.error".localized))
                                        }
                                    }) {
                                        ItemView(id: item.idStr,
                                                 amount: item.amount,
                                                 unlockHeight: item.unlockHeight.description,
                                                 releaseHeight: item.releaseHeight.description,
                                                 address: item.address,
                                                 isSelected: viewModel.isSelected(item: item),
                                                 isEnable: item.isEnable,
                                                 isVoteLock: viewModel.withdrawType == .voteLocked
                                        )
                                    }
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
                    viewModel.withdrawItems()
                }
            }
        }
        .navigationBarTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .completed(_) = viewModel.dataState, viewModel.enableItems.count > 0 {
                    if viewModel.isChoosedAll {
                        Button("button.cancel".localized) {
                            viewModel.cancelAll()
                        }
                    } else if !viewModel.isChoosedAll {
                        Button("button.all".localized) {
                            viewModel.chooseAll()
                        }
                    }
                }
            }
        }
    }
    
    struct ItemView: View {
        let id: String
        let amount: String
        let unlockHeight: String
        let releaseHeight: String
        let address: String
        let isSelected: Bool
        let isEnable: Bool
        let isVoteLock: Bool
        
        var body: some View {
            VStack(spacing: 1) {
                Text("safe_zone.safe4.vote.record.id".localized + ": "  + id)
                    .themeSubhead1(color: .themeLeah)
                Text("safe_withdraw.amount.locked".localized + ": " + amount)
                    .themeSubhead1(color: .themeLeah)
                Text("safe_withdraw.unlock.height".localized + ": " + unlockHeight)
                    .themeSubhead1(color: .themeLeah)
                if isVoteLock {
                    Text("safe_withdraw.release.height".localized + ": " + releaseHeight)
                        .themeSubhead1(color: .themeLeah)
                    Text("safe_zone.safe4.vote.record.address".localized + ": " + address)
                        .themeSubhead1(color: .themeLeah)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }

            }
            
            if isEnable {
                isSelected ? Image("checkbox_active_24") : Image("checkbox_diactive_24")
            }else {
                Image("")
                    .resizable()
                    .frame(width: 24, height: 24)
            }
        }
    }

}
