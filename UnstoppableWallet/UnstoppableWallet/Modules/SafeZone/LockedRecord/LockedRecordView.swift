import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import UIKit
import AdvancedList
import BigInt

struct LockedRecordView: View {
    @StateObject private var viewModel: LockedRecordViewModel
    @Environment(\.presentationMode) private var presentationMode
    
    init(viewModel: LockedRecordViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeNavigationStack{
            ThemeView {
                ZStack {
                    VStack{
                        list()
                        if case .loading = viewModel.dataState, !viewModel.viewItems.isEmpty {
                            ProgressView()
                        }
                        if !viewModel.hasMoreItems {
                            Text("loadData.nomore".localized)
                                .themeSubhead1(color: .themeLeah, alignment: .center)
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
            .navigationBarTitle("safe_zone.safe4.account.lock".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar() }
            .task(id: viewModel.sendState) {
                if case let .success(message) = viewModel.sendState {
                    HudHelper.instance.show(banner: .success(string: message ?? ""))
                    presentationMode.wrappedValue.dismiss()
                }
                
                if case let .failed(error) = viewModel.sendState {
                    HudHelper.instance.show(banner: .error(string: error ?? ""))
                }
            }
        }
    }
    @ToolbarContentBuilder func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                Coordinator.shared.present(type: .bottomSheet) { isPresented in
                    confirmWithdrawView(ids: [], isAll: true, isPresented: isPresented)
                }
            }) {
                Text("一键提现".localized)
                    .themeSubhead1(color: viewModel.withdrawEnableIds.count > 0 ? .themeYellow : .themeGray)
            }
            .disabled(viewModel.withdrawEnableIds.count == 0)
        }
    }
    
    @ViewBuilder
    private func list() -> some View {
        AdvancedList(viewModel.viewItems, content: { item in
            view(for: item)
        }, emptyStateView: {}, errorStateView: {_ in }, loadingStateView: {})
        .pagination(.init(type: .lastItem, shouldLoadNextPage: loadNextItems) {})
    }
    
    @ViewBuilder
    private func view(for item: WithdrawItemRecord) -> some View {
        ItemView(id: item.idStr,
                 amount: item.amount,
                 unlockHeight: item.unlockHeight.description,
                 releaseHeight: item.releaseHeight?.description,
                 address: item.address,
                 isEnableWithdraw: item.withdrawEnable,
                 isShowAddLock: item.addLockDayEnable)
        {
            Coordinator.shared.present(type: .bottomSheet) { isPresented in
                confirmWithdrawView(ids: [BigUInt(item.id)], isPresented: isPresented)
            }
        } addLockAction: {
            guard let vm = AddLockDaysModule.viewModel(ids: [BigUInt(item.id)]) else { return }
            Coordinator.shared.present { _ in
                AddLockDaysView(viewModel: vm)
            }
        }
    }
    
    @ViewBuilder private func confirmWithdrawView(ids: [BigUInt], isAll: Bool = false, isPresented: Binding<Bool>) -> some View {
        
        BottomSheetView(
            icon: .warning,
            title: "safe_zone.safe4.withdraw".localized,
            items: [
                .highlightedDescription(text: "提现后将不再产生收益，确定提取吗？", style: .warning),
            ],
            buttons: [
                .init(style: .yellow, title: "button.ok".localized) {
                    if isAll {
                        viewModel.allWithdraw()
                    }else {
                        viewModel.withdraw(ids: ids)
                    }
                    
                    isPresented.wrappedValue = false
                },
                .init(style: .transparent, title: "button.cancel".localized) {
                    isPresented.wrappedValue = false
                }
            ],
            isPresented: isPresented
        )
    }
    
    private func loadNextItems() {
        guard viewModel.hasMoreItems, viewModel.viewItems.count > 0, viewModel.dataState != .loading else { return }
        viewModel.loadMore()
    }
    
    @ViewBuilder
    private func loadingHud() ->  some View {
        Color.white.opacity(0.01)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {}
        ProgressView()
    }
    
    struct ItemView: View {
        let id: String
        let amount: String
        let unlockHeight: String
        let releaseHeight: String?
        let address: String?
        let isEnableWithdraw: Bool
        let isShowAddLock: Bool
        let withdrawAction: () -> Void
        let addLockAction: () -> Void
        
        var body: some View {
            VStack(spacing: 4) {
                Text("safe_zone.safe4.vote.record.id".localized + ": "  + id)
                    .themeSubhead1(color: .themeLeah)
                Text("safe_withdraw.amount.locked".localized + ": " + amount)
                    .themeSubhead1(color: .themeLeah)
                Text("safe_withdraw.unlock.height".localized + ": " + unlockHeight)
                    .themeSubhead1(color: .themeLeah)
                if let releaseHeight {
                    Text("safe_withdraw.release.height".localized + ": " + releaseHeight)
                        .themeSubhead1(color: .themeLeah)
                }
                if let address {
                    Text("safe_zone.safe4.vote.record.address".localized + ": " + address)
                        .themeSubhead1(color: .themeLeah)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }

                HStack(spacing: .margin16) {
                    Button(action: {
                        if isEnableWithdraw {
                            withdrawAction()
                        }
                    }) {
                        Text("safe_zone.safe4.withdraw".localized)
                    }
                    .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                    .disabled(!isEnableWithdraw)
                    
                    if isShowAddLock {
                        Button(action: {
                            addLockAction()
                        }) {
                            Text("safe_zone.safe4.contract.addlockday".localized)
                        }
                        .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                    }
                }
            }
        }
    }
}
