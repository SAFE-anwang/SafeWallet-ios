import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import ComponentKit
import HUD
import UIKit
import AdvancedList
import BigInt

struct LockedRecordView: View {
    @StateObject private var viewModel: LockedRecordViewModel
    @Environment(\.presentationMode) private var presentationMode
    private var uiNavController: UINavigationController
    @State private var lockedRecordItemAction: LockedRecordViewModel.LockedRecordItemAction?
    
    init(viewModel: LockedRecordViewModel, uiNavController: UINavigationController) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.uiNavController = uiNavController
    }
    
    var body: some View {
        ThemeView {
            ZStack {
                VStack{
                    list()
                    if case .loading = viewModel.dataState, !viewModel.viewItems.isEmpty {
                        ProgressView()
                    }
                }

                if case .loading = viewModel.dataState, viewModel.viewItems.isEmpty {
                    ProgressView()
                }
                
                if case .items = viewModel.dataState, viewModel.viewItems.isEmpty {
                    PlaceholderViewNew(image: Image("no_data_48"), text: "coin_markets.empty".localized)
                }
                
                if case .loading = viewModel.sendState {
                    loadingHud()
                }
            }
        }
        .navigationBarTitle("safe_zone.safe4.account.lock".localized)
        .navigationBarTitleDisplayMode(.inline)
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
            lockedRecordItemAction = .withdraw(id: BigUInt(item.id))
        } addLockAction: {
            guard let vc = AddLockDaysModule.viewController(ids: [BigUInt(item.id)]) else { return }
            uiNavController.pushViewController(vc, animated: true)
        }
        .modifier(ThemeListStyleModifier(themeListStyle: .lawrence, selected: false))
        .sheet(item: $lockedRecordItemAction) { action in
            if case let .withdraw(id)  = action {
                if #available(iOS 16, *) {
                    ViewWrapper(BottomSheetModule.withdrawConfirmation() {
                        viewModel.withdraw(id: id)
                    }).presentationDetents([.medium])
                } else {
                    ViewWrapper(BottomSheetModule.withdrawConfirmation() {
                        viewModel.withdraw(id: id)
                    })
                }
            }
        }
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
