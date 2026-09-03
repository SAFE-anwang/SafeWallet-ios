import SwiftUI

struct SafeDappLogoView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SafeDappLogoViewModel
    @State private var isShowingImagePicker = false
    @State private var showConfirm = false

    init(viewModel: SafeDappLogoViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            ZStack {
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            infoView
                            logoView
                            if let fee = viewModel.fee {
                                feeView(fee: "\(fee.safe4FormattedAmount) SAFE")
                            }
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button(action: { showConfirm = true }) {
                        Text("safe_dapp.set_logo".localized)
                    }
                    .disabled(viewModel.sendState != .ready)
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                }
                if viewModel.sendState == .sending {
                    ProgressView()
                }
            }
        }
        .navigationBarTitle("safe_dapp.logo".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImage)
        }
        .alert("safe_dapp.set_logo_confirm".localized, isPresented: $showConfirm, actions: {
            Button("button.cancel".localized, role: .cancel) {}
            Button("button.confirm".localized) {
                viewModel.upload { state in
                    switch state {
                    case .completed:
                        HudHelper.instance.show(banner: .success(string: "safe_dapp.logo_success_message".localized))
                        presentationMode.wrappedValue.dismiss()
                    case let .failed(message):
                        HudHelper.instance.show(banner: .error(string: message))
                    default: ()
                    }
                }
            }
        })
    }

    @ViewBuilder private var infoView: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(viewModel.info.name)
                .themeSubhead1(color: .themeLeah)
            Text("ID: \(viewModel.info.id.description)")
                .themeSubhead2(color: .themeGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    @ViewBuilder private var logoView: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text("safe_dapp.logo".localized.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
            HStack {
                Group {
                    if let selectedImage = viewModel.selectedImage {
                        Image(uiImage: selectedImage).resizable()
                    } else {
                        Image("safe-anwang_trx_32").resizable().scaledToFit()
                    }
                }
                .clipShape(Circle())
                .frame(width: .iconSize48, height: .iconSize48)
                .onTapGesture { isShowingImagePicker = true }

                Spacer()

                Button(action: { isShowingImagePicker = true }) {
                    Text("safe_dapp.choose_logo".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(PrimaryButtonStyle(style: .yellow))
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.logoCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.logoCautionState))
        }
    }

    @ViewBuilder private func feeView(fee: String) -> some View {
        HStack(spacing: .margin8) {
            Image("circle_warning_24").themeIcon(color: .themeLeah)
            Text("safe_dapp.logo_fee".localized(fee))
                .themeSubhead2(color: .themeLeah)
            Spacer()
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
}
