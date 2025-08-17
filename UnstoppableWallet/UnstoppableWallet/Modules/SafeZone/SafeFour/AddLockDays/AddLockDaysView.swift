import Foundation
import SwiftUI
import Combine
import EvmKit
import Kingfisher
import MarketKit
import ComponentKit
import HUD
import UIKit

struct AddLockDaysView: View {
    @StateObject var viewModel: AddLockDaysViewModel
    @Environment(\.presentationMode) private var presentationMode
    @State var addLockDaysAlertPresented = false

    init(viewModel: AddLockDaysViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        ListSection {
                            ForEach(viewModel.viewItems, id: \.lockID) { item in
                                ClickableRow(action: {}) {
                                    ItemView(item: item, minusAction: {
                                        item.minus()
                                    } ,plusAction: {
                                        item.plus()
                                    } ,addLockDaysAction: {
                                        addLockDaysAlertPresented = true
                                    })
                                }.sheet(isPresented: $addLockDaysAlertPresented) {
                                    if #available(iOS 16, *) {
                                        ViewWrapper(BottomSheetModule.addLockDaysConfirmation(days: item.selectedLockedDays.description) {
                                            viewModel.addLock(info: item)
                                        }).presentationDetents([.medium])
                                    } else {
                                        ViewWrapper(BottomSheetModule.addLockDaysConfirmation(days: item.selectedLockedDays.description) {
                                            viewModel.addLock(info: item)
                                        })
                                    }
                                }
                            }
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }
                if case .completed = viewModel.state {
                    if viewModel.viewItems.isEmpty {
                        PlaceholderViewNew(image: Image("no_data_48"), text: "coin_markets.empty".localized)
                    }else {
                        
                    }
                }
                
                if case .loading = viewModel.state {
                    Color.white.opacity(0.01)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {}
                    ProgressView()
                }
            }
        }
        .navigationBarTitle("safe_zone.safe4.node.locked.days.add.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.state) {
            if case let .success(message) = viewModel.state {
                HudHelper.instance.show(banner: .success(string: message ?? ""))
                presentationMode.wrappedValue.dismiss()
            }
            
            if case let .failed(error) = viewModel.state {
                HudHelper.instance.show(banner: .error(string: error ?? ""))
            }
        }
    }
    
    struct ItemView: View {
        @ObservedObject var item: AddLockDaysViewModel.LockInfo
        let minusAction: () -> Void
        let plusAction: () -> Void
        let addLockDaysAction: () -> Void

        var body: some View {
            VStack(spacing: 5) {
                subView(title: "safe_zone.safe4.vote.record.id".localized, value: item.lockID.description)
                subView(title: "safe_zone.safe4.vote.record.amount".localized, value: item.lockedAmount.safe4FomattedAmount + "SAFE")
                subView(title: "safe_zone.safe4.node.locked.days".localized, value: item.lockedDays.description + "safe_zone.safe4.node.locked.days.title".localized)
                subView(title: "safe_zone.safe4.node.locked.days.max".localized, value: item.maxLockDays.description + "safe_zone.safe4.node.locked.days.title".localized)
                daysControlView(days: item.selectedLockedDays.description + "safe_zone.safe4.node.locked.days.title".localized)
                Button(action: {
                    addLockDaysAction()
                }) {
                    Text("safe_zone.safe4.node.locked.days.add.btn.title".localized)
                }
                .buttonStyle(PrimaryButtonStyle(style: .yellow))
            }
        }
        
        @ViewBuilder private func subView(title: String, value: String) -> some View {
            HStack{
                Text(title)
                    .themeSubhead1(color: .themeGray, alignment: .leading)
                Spacer()
                Text(value)
                    .themeSubhead1(color: .themeLeah, alignment: .trailing)
            }
        }
        
        @ViewBuilder private func daysControlView(days: String) -> some View {
            HStack(spacing: 5){
                Spacer()
                Button(action: {
                    minusAction()
                }) {
                    Image("circle_minus_24")
                }
                Text(days)
                    .themeSubhead1(color: .themeLeah, alignment: .center)
                    .layoutPriority(1)
                Button(action: {
                    plusAction()
                }) {
                    Image("circle_plus_24")
                }
                Spacer()
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
    }
}
