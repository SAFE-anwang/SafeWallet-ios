import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI
import ComponentKit
import HUD
import UIKit

struct LockedRecoardView: View {
    @StateObject private var viewModel: LockedRecoardViewModel
    @Environment(\.presentationMode) private var presentationMode
    private var uiNavController: UINavigationController
    @State var withdrawAlertPresented = false

    init(viewModel: LockedRecoardViewModel, uiNavController: UINavigationController) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.uiNavController = uiNavController
    }
    
    var body: some View {
        ThemeView {
            ZStack {
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        ListSection {
                            ForEach(viewModel.viewItems, id: \.id) { item in
                                ClickableRow(action: {}) {
                                    ItemView(id: item.idStr,
                                             amount: item.amount,
                                             unlockHeight: item.unlockHeight.description,
                                             releaseHeight: item.releaseHeight.description,
                                             address: item.address,
                                             isEnableWithdraw: item.withdrawEnable,
                                             isShowAddLock: item.addLockDayEnable)
                                        {
                                            withdrawAlertPresented = true
                                        } addLockAction: {
                                            guard let vc = AddLockDaysModule.viewController(ids: [item.id]) else { return }
                                            uiNavController.pushViewController(vc, animated: true)
                                        }

                                }.sheet(isPresented: $withdrawAlertPresented) {
                                    if #available(iOS 16, *) {
                                        ViewWrapper(BottomSheetModule.withdrawConfirmation() {
                                            viewModel.withdraw(id: item.id)
                                            withdrawAlertPresented = false
                                        }).presentationDetents([.medium])
                                    } else {
                                        ViewWrapper(BottomSheetModule.withdrawConfirmation() {
                                            viewModel.withdraw(id: item.id)
                                            withdrawAlertPresented = false
                                        })
                                    }
                                }
                            }
                            
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .onAppear {
                                        viewModel.loadMore()
                                    }
                            } else {
                                if viewModel.viewItems.count > 0 {
                                    Text("没有更多内容了")
                                        .frame(height: .margin40)
                                        .foregroundColor(.secondary)
                                }
                                
                            }
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }.background(GeometryReader {
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: $0.frame(in: .global).minY
                    )
                })
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    viewModel.checkIfShouldLoadMore(offset: offset)
                }
                
                if case .completed = viewModel.dataState {
                    if viewModel.viewItems.isEmpty {
                        PlaceholderViewNew(image: Image("no_data_48"), text: "coin_markets.empty".localized)
                    }
                }
                
                if case .loading = viewModel.dataState {
                    loadingHud()
                } else if case .loading = viewModel.sendState {
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
    
    @ViewBuilder private func loadingHud() ->  some View {
        Color.white.opacity(0.01)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {}
        ProgressView()
    }
    
    struct ScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
    
    struct ItemView: View {
        let id: String
        let amount: String
        let unlockHeight: String
        let releaseHeight: String
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
                Text("safe_withdraw.release.height".localized + ": " + releaseHeight)
                    .themeSubhead1(color: .themeLeah)
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

    struct ItemPrimaryButtonStyle: ButtonStyle {
        let style: Style

        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 5, leading: .margin32, bottom: 5, trailing: .margin32))
                .font(.themeHeadline2)
                .foregroundColor(style.foregroundColor(isEnabled: isEnabled, isPressed: configuration.isPressed))
                .background(style.backgroundColor(isEnabled: isEnabled, isPressed: configuration.isPressed))
                .clipShape(Capsule(style: .continuous))
                .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
        }

        enum Style {
            case yellow
            case red
            case gray
            case transparent

            init(style: PrimaryButton.Style) {
                switch style {
                case .yellow: self = .yellow
                case .red: self = .red
                case .gray: self = .gray
                case .transparent: self = .transparent
                }
            }

            func foregroundColor(isEnabled: Bool, isPressed: Bool) -> Color {
                switch self {
                case .yellow: return isEnabled ? .themeDark : .themeGray50
                case .red, .gray: return isEnabled ? .themeClaude : .themeGray50
                case .transparent: return isEnabled ? (isPressed ? .themeGray : .themeLeah) : .themeGray50
                }
            }

            func backgroundColor(isEnabled: Bool, isPressed: Bool) -> Color {
                switch self {
                case .yellow: return isEnabled ? (isPressed ? .themeYellow50 : .themeYellow) : .themeSteel20
                case .red: return isEnabled ? (isPressed ? .themeRed50 : .themeLucian) : .themeSteel20
                case .gray: return isEnabled ? (isPressed ? .themeNina : .themeLeah) : .themeSteel20
                case .transparent: return .clear
                }
            }
        }
    }
}
