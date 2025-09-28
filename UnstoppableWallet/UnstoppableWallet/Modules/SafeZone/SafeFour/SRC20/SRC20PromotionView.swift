import SwiftUI
import ComponentKit
import HUD
import Kingfisher

struct SRC20PromotionView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SRC20PromotionViewModel
    @State private var isShowingImagePicker = false
    @State private var isShowAlert: Bool = false

    init(viewModel: SRC20PromotionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            tokenInfoView(name: viewModel.token.name, symbol: viewModel.token.symbol)
                            logoView()
                            if let fee = viewModel.fee {
                                feeView(fee: "\(fee) SAFE")
                            }
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button(action: {
                        isShowAlert = true
                    }) {
                        HStack(spacing: .margin8) {
                            Text("button.next".localized)
                        }
                    }
                    .disabled(!viewModel.isSendAble)
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                }
                if case .sending = viewModel.sendState {
                    ProgressView()
                }
            }
        }
        .navigationBarTitle("SRC20_Promotion".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImage)
        }
        .alert("SRC20_Promotion_Hint".localized, isPresented: $isShowAlert, actions: {
            HStack{
                Button("button.cancel".localized) {
                    isShowAlert = false
                }
                Button("button.confirm".localized) {
                    
                    viewModel.upload { state in
                        switch state {
                        case .notReady, .ready, .sending: ()
                        case .completed:
                            DispatchQueue.main.async {
                                HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                                presentationMode.wrappedValue.dismiss()
                            }
                            
                        case .failed:
                            DispatchQueue.main.async {
                                HudHelper.instance.show(banner: .error(string: "transactions.failed".localized))
                            }
                        }
                    }
                    isShowAlert = false
                }
            }
        })
    }
    
    @ViewBuilder private func tokenInfoView(name: String, symbol: String) -> some View {
        VStack(spacing: .margin8) {
            Text("SRC20_Edit_Name".localized + " \(name)")
                .themeSubhead1(color: .themeLeah)
            
            Text("SRC20_Edit_Symbol".localized + " \(symbol)")
                .themeSubhead1(color: .themeLeah)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
    
    @ViewBuilder private func logoView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Asset_Logo".localized)
            HStack {
                if let uiImage = viewModel.selectedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .clipShape(Circle())
                        .frame(width: .iconSize48, height: .iconSize48)
                        .onTapGesture {
                            isShowingImagePicker = true
                        }
                }else {
                    KFImage.url(URL(string: viewModel.token.logoURI ?? ""))
                        .resizable()
                        .placeholder {
                            Image("safe-anwang_trx_32")
                                .resizable()
                                .scaledToFit()
                                .colorMultiply(.blue)
                        }
                        .clipShape(Circle())
                        .frame(width: .iconSize48, height: .iconSize48)
                        .onTapGesture {
                            isShowingImagePicker = true
                        }
                }
                Spacer()
            }
        }
    }
    
    @ViewBuilder private func feeView(fee: String) -> some View {
        HStack(spacing: .margin8) {
            Image("circle_warning_24")
                .themeIcon(color: .themeLeah)

            Text("SRC20_Promotion_Fee".localized(fee))
            Spacer()
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        .modifier(CautionBorder(cautionState: $viewModel.balanceCautionState))
        .modifier(CautionPrompt(cautionState: $viewModel.balanceCautionState))
    }
    
    struct SectionHeader: View {
        let text: String

        var body: some View {
            Text(text.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
        }
    }
}
