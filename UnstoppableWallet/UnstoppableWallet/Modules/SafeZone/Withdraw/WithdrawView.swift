import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import AdvancedList
import BigInt

struct WithdrawView: View {
    @StateObject var viewModel: WithdrawViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    init(viewModel: WithdrawViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ZStack {
                    VStack{
                        list(items: viewModel.viewItems)
                        if case .loading = viewModel.dataState, !viewModel.viewItems.isEmpty {
                            ProgressView()
                        }
                        if !viewModel.hasMoreItems, viewModel.viewItems.count > 0 {
                            Text("loadData.nomore".localized)
                                .themeSubhead1(color: .themeLeah, alignment: .center)
                        }
                        if /*case .items = viewModel.dataState, */!viewModel.viewItems.isEmpty {
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
                            .padding(EdgeInsets(top: 0, leading: .margin16, bottom: 0, trailing: .margin16))
                            .buttonStyle(PrimaryButtonStyle(style: .yellow))
                            .disabled(!viewModel.withdrawEnabled)
                        }
                    }

                    if case .loading = viewModel.dataState, viewModel.viewItems.isEmpty {
                        ProgressView()
                    }
                    
                    if case .items = viewModel.dataState, viewModel.viewItems.isEmpty {
                        PlaceholderViewNew(icon: "no_data_48", title: "coin_markets.empty".localized)
                    }
                    
                    if case .loading = viewModel.sendState {
                        loadingHud()
                    }
                }
            }
            .navigationBarTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.withdrawType == .voteLocked {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Coordinator.shared.present(type: .bottomSheet) { isPresented in
                                confirmWithdrawView(ids: [], isAll: true, isPresented: isPresented)
                            }
                        }) {
                            Text("一键提现".localized)
                                .themeSubhead1(color: viewModel.enableItems.count > 0 ? .themeYellow : .themeGray)
                        }
                        .disabled(viewModel.enableItems.count == 0)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func confirmWithdrawView(ids: [BigUInt], isAll: Bool = false, isPresented: Binding<Bool>) -> some View {
        
        BottomSheetView(
            icon: .warning,
            title: "safe_zone.safe4.withdraw".localized,
            items: [
                .highlightedDescription(text: "提现后将不再产生收益，确定提取吗？", style: .warning),
            ],
            buttons: [
                .init(style: .yellow, title: "button.ok".localized) {
                    viewModel.allWithdraw()
                    isPresented.wrappedValue = false
                },
                .init(style: .transparent, title: "button.cancel".localized) {
                    isPresented.wrappedValue = false
                }
            ],
            isPresented: isPresented
        )
    }
    
    @ViewBuilder
    private func loadingHud() ->  some View {
        Color.white.opacity(0.01)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {}
        ProgressView()
    }
    
    @ViewBuilder
    private func list(items: [WithdrawItem]) -> some View {
        AdvancedList(items, content: { item in
            ClickableRow(action: {
                if item.isSelEnable {
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
                         isEnable: item.isSelEnable,
                         isVoteLock: viewModel.withdrawType == .voteLocked
                )
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }, emptyStateView: {}, errorStateView: {_ in }, loadingStateView: {})
        .pagination(.init(type: .lastItem, shouldLoadNextPage: loadNextItems) {})
    }
    
    private func loadNextItems() {
        guard viewModel.hasMoreItems, viewModel.viewItems.count > 0, viewModel.dataState != .loading else { return }
        viewModel.loadMore()
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
