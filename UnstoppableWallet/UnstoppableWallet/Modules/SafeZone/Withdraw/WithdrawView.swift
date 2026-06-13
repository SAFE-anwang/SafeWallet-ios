import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import BigInt

struct WithdrawView: View {
    @StateObject var viewModel: WithdrawViewModel
    @Environment(\.presentationMode) private var presentationMode
    @Binding private var isPresented: Bool
    
    init(viewModel: WithdrawViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }
    
    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ZStack {
                    VStack{
                        list(items: viewModel.viewItems)
                        if viewModel.isLoadingNextPage {
                            ProgressView()
                        }
                        if !viewModel.hasMoreItems, !viewModel.isRefreshing, !viewModel.isLoadingNextPage, viewModel.viewItems.count > 0 {
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
            .refreshable {
                await viewModel.refresh()
            }
            .navigationBarTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image("close")
                    }
                }
                
                if viewModel.withdrawType == .voteLocked {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Coordinator.shared.present(type: .bottomSheet) { isPresented in
                                confirmWithdrawView(ids: [], isAll: true, isPresented: isPresented)
                            }
                        }) {
                            Text("safe_zone.one_click_withdraw".localized)
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
            items: [
                .title(icon: nil, title: "safe_zone.safe4.withdraw".localized),
                .highlightedDescription(text: "safe_zone.withdraw_no_more_yield".localized, type: .caution, style: .structured),
                .buttonGroup(.init(buttons: [
                    .init(style: .yellow, title: "button.ok".localized) {
                        viewModel.allWithdraw()
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
                        isPresented.wrappedValue = false
                        
                    },
                    .init(style: .transparent, title: "button.cancel".localized) {
                        isPresented.wrappedValue = false
                    }
                ],
                alignment: .horizontal)),
            ],
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
        ScrollView {
            LazyVStack(spacing: .margin12) {
                ForEach(items) { item in
                    ClickableRow(action: {
                        if item.isSelEnable {
                            viewModel.choose(item: item)
                        } else {
//                            HudHelper.instance.show(banner: .error(string: "safe_withdraw.votelocked.error".localized))
                        }
                    }) {
                        ItemView(
                            id: item.idStr,
                            amount: item.amount,
                            unlockHeight: item.unlockHeight.description,
                            releaseHeight: item.releaseHeight.description,
                            address: item.address,
                            isSelected: viewModel.isSelected(item: item),
                            isEnable: item.isSelEnable,
                            isVoteLock: viewModel.withdrawType == .voteLocked
                        )
                    }
                    .padding(.horizontal, 12)
                    .onAppear {
                        if item.id == items.last?.id {
                            loadNextItems()
                        }
                    }
                }
            }
        }
    }
    
    private func loadNextItems() {
        guard viewModel.hasMoreItems,
              !viewModel.isRefreshing,
              !viewModel.isLoadingNextPage,
              viewModel.viewItems.count > 0
        else { return }
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
            HStack(spacing: .margin12) {
                VStack(alignment: .leading, spacing: .margin8) {
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

                Spacer(minLength: 0)

                if isEnable {
                    isSelected ? Image("checkbox_active_24") : Image("checkbox_diactive_24")
                } else {
                    Color.clear
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

}
