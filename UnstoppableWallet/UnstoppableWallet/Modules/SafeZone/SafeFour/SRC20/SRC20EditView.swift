import SwiftUI
import ComponentKit
import HUD

struct SRC20EditView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SRC20EditViewModel
    @FocusState private var focusField: SRC20EditViewModel.FocusField?
    @State private var isShowAlert: Bool = false

    init(viewModel: SRC20EditViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            tokenInfoView(name: viewModel.token.name, symbol: viewModel.token.symbol)
                            whitePaperUrlInputView()
                            orgNameInputView()
                            officialUrlInputView()
                            descriptionInputView()
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
                    .disabled(!viewModel.isUpdateAble)
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                }
                if case .sending = viewModel.sendState {
                    ProgressView()
                }
                if case .loading = viewModel.dataState {
                    ProgressView()
                }
            }

        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) {
                    if focusField != nil {
                        focusField = nil
                    }else {
                        UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusField = nil
        }
        .navigationBarTitle("SRC20_Edit".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("SRC20_Edit_Hint".localized, isPresented: $isShowAlert, actions: {
            HStack{
                Button("button.cancel".localized) {
                    isShowAlert = false
                }
                Button("button.confirm".localized) {
                    
                    viewModel.update { state in
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
            Text("SRC20_Edit_Name".localized + "\(name)")
                .themeSubhead1(color: .themeLeah)
            
            Text("SRC20_Edit_Symbol".localized + "\(symbol)")
                .themeSubhead1(color: .themeLeah)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
    
    @ViewBuilder private func whitePaperUrlInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Edit_White_Paper".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.whitePaperUrl, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .whitePaperUrl)
                
                if !viewModel.whitePaperUrl.isEmpty {
                    Button(action: {
                        viewModel.whitePaperUrl = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.whitePaperUrlCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.whitePaperUrlCautionState))
        }
    }
    
    @ViewBuilder private func orgNameInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Edit_Org".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.orgName, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .orgName)
                
                if !viewModel.orgName.isEmpty {
                    Button(action: {
                        viewModel.orgName = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.orgNameCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.orgNameCautionState))
        }
    }
    
    @ViewBuilder private func officialUrlInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Edit_Official".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.officialUrl, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .officialUrl)
                
                if !viewModel.officialUrl.isEmpty {
                    Button(action: {
                        viewModel.officialUrl = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.officialUrlCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.officialUrlCautionState))
        }
    }
    
    @ViewBuilder private func descriptionInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Edit_Desc".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.description, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .description)
                
                if !viewModel.description.isEmpty {
                    Button(action: {
                        viewModel.description = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.descriptionCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.descriptionCautionState))
        }
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

