import Foundation
import SwiftUI
import ComponentKit
import HUD
import Kingfisher

struct SRC20ManagerView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SRC20ManagerViewModel
    @State private var presentDestination: PresentDestination?
    @State private var editType: SRC20EditType? = nil
    private var uiNavController: UINavigationController
    init(viewModel: SRC20ManagerViewModel, uiNavController: UINavigationController) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.uiNavController = uiNavController
    }
    
    var body: some View {
        ThemeView {
            switch viewModel.dataState {
            case .loading:
                ProgressView()
            case let .completed(items):
                if items.isEmpty {
                    PlaceholderViewNew(image: Image("no_data_48"), text: "暂无发行资产".localized)
                }else {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            ListSection {
                                ForEach(items, id: \.id) { item in
                                
                                    ClickableRow(action: {}) {
                                        ItemView(token: item.token) {
                                            guard let vc = SRC20ManagerModule.editViewController(token: item.token, type: .edit) else { return }
                                            self.uiNavController.pushViewController(vc, animated: true)
                                        } promotionAction: {
                                            guard let vc = SRC20ManagerModule.editViewController(token: item.token, type: .promotion) else { return }
                                            self.uiNavController.pushViewController(vc, animated: true)
                                        } addAction: {
                                            guard let vc = SRC20ManagerModule.editViewController(token: item.token, type: .additional) else { return }
                                            self.uiNavController.pushViewController(vc, animated: true)
                                        } destroyAction: {
                                            guard let vc = SRC20ManagerModule.editViewController(token: item.token, type: .destroy) else { return }
                                            self.uiNavController.pushViewController(vc, animated: true)
                                        }

                                    }
                                }
                            }
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                    }
                }

            case .failed(_):
                SyncErrorView {}
            }
        }
        .navigationBarTitle("SRC20_Deploy_Promotion".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    struct ItemView: View {
        var token: Safe4CustomTokenRecord
        let editAction: () -> Void
        let promotionAction: () -> Void
        let addAction: () -> Void
        let destroyAction: () -> Void
        
        var body: some View {
            VStack(spacing: .margin8) {
                coinView(logoUrl: token.logoURI ?? "", title: token.symbol, subTitle: token.name)
                addressView(title: "SRC20_Info_Contract".localized, address: token.address)
                addressView(title: "SRC20_Info_Creator".localized, address: token.creator)
                buttonsView()
            }
        }
        
        @ViewBuilder private func coinView(logoUrl: String, title: String, subTitle: String) -> some View {
            HStack(spacing: .margin12) {
                KFImage.url(URL(string: logoUrl))
                    .resizable()
                    .placeholder {
                        Image("safe-anwang_trx_32")//Circle().fill(Color.themeSteel20)
                    }
                    .clipShape(Circle())
                    .frame(width: .iconSize32, height: .iconSize32)
                VStack {
                    Text(title)
                        .themeSubhead1(color: .themeLeah)
                    Text(subTitle)
                        .themeSubhead1(color: .themeLeah)
                }
            }
        }
        
        @ViewBuilder private func addressView(title: String, address: String) -> some View {
            HStack{
                Text(title)
                    .themeSubhead1(color: .themeLeah, alignment: .leading)
                    .fixedSize()
                Button(action: {
                    UIPasteboard.general.string = address
                    HudHelper.instance.show(banner: .copied)
                }) {
                    Text(address)
                        .themeSubhead1(color:.blue, alignment: .leading)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }.frame(maxWidth: .infinity)
            }
        }
        
        @ViewBuilder private func buttonsView() -> some View {
            HStack{
                Button(action: {
                    editAction()
                }) {
                    Text("SRC20_Info_Edit".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                
                Button(action: {
                    promotionAction()
                }) {
                    Text("SRC20_Info_Promotion".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                
                Button(action: {
                    addAction()
                }) {
                    Text("SRC20_Info_Add".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                .disabled(!token.canAdditionalIssuance)
                
                Button(action: {
                    destroyAction()
                }) {
                    Text("SRC20_Info_Destroy".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(ItemPrimaryButtonStyle(style: .yellow))
                .disabled(!token.canDestroy)
            }
        }
    }
}
