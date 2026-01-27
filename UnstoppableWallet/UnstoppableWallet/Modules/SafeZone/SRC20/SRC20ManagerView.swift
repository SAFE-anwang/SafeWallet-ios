import Foundation
import SwiftUI
import Kingfisher

struct SRC20ManagerView: View {
    @StateObject var viewModel: SRC20ManagerViewModel
    @State private var presentDestination: PresentDestination?
    @State private var selectedViewModel: (any ObservableObject)? = nil
    @State private var path = NavigationPath()
    
    init(viewModel: SRC20ManagerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeNavigationStack(path: $path) {
            ThemeView {
                switch viewModel.dataState {
                case .loading:
                    ProgressView()
                case let .completed(items):
                    if items.isEmpty {
                        PlaceholderViewNew(icon: "no_data_48", title: "暂无发行资产".localized)
                    }else {
                        ScrollableThemeView {
                            VStack(spacing: .margin8) {
                                ListSection {
                                    ForEach(items, id: \.id) { item in
                                        ClickableRow(action: {}) {
                                            ItemView(token: item.token) {
                                                guard let viewMoel = SRC20ManagerModule.detailViewModel(token: item.token, type: .edit) as? SRC20EditViewModel else { return }
                                                selectedViewModel = viewMoel
                                                path.append(SRC20ManagerViewModel.DetailViewType(editType: .edit, viewModel: viewMoel))
                                            } promotionAction: {
                                                guard let viewMoel = SRC20ManagerModule.detailViewModel(token: item.token, type: .promotion) as? SRC20PromotionViewModel else { return }
                                                selectedViewModel = viewMoel
                                                path.append(SRC20ManagerViewModel.DetailViewType(editType: .promotion, viewModel: viewMoel))
                                            } addAction: {
                                                guard let viewMoel = SRC20ManagerModule.detailViewModel(token: item.token, type: .additional) as? SRC20AdditionalViewModel else { return }
                                                selectedViewModel = viewMoel
                                                path.append(SRC20ManagerViewModel.DetailViewType(editType: .additional, viewModel: viewMoel))
                                            } destroyAction: {
                                                guard let viewMoel = SRC20ManagerModule.detailViewModel(token: item.token, type: .destroy) as? SRC20DestroyViewModel else { return }
                                                selectedViewModel = viewMoel
                                                path.append(SRC20ManagerViewModel.DetailViewType(editType: .destroy, viewModel: viewMoel))
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                        }

                        .navigationDestination(for: SRC20ManagerViewModel.DetailViewType.self) { type in
                            switch type.editType {
                            case .edit:
                                if let viewModel = type.viewModel as? SRC20EditViewModel {
                                    SRC20EditView(viewModel: viewModel)
                                }
                                
                            case .promotion:
                                if let viewModel = type.viewModel as? SRC20PromotionViewModel {
                                    SRC20PromotionView(viewModel: viewModel)
                                }
                                
                            case .additional:
                                if let viewModel = type.viewModel as? SRC20AdditionalViewModel {
                                    SRC20AdditionalView(viewModel: viewModel)
                                }
                                
                            case .destroy:
                                if let viewModel = type.viewModel as? SRC20DestroyViewModel {
                                    SRC20DestroyView(viewModel: viewModel)
                                }
                            }
                        }
                    }

                case .failed(_):
                    SyncErrorView {}
                }
            }
            .navigationBarTitle("SRC20_Deploy_Promotion".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
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
                        Image("safe-anwang_trx_32")
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
