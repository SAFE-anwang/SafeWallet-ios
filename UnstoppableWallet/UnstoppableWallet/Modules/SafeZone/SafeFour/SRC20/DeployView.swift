import SwiftUI
import ComponentKit
import HUD

struct DeployView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: DeployViewModel
    @FocusState private var focusField: DeployViewModel.FocusField?
    @State private var isShowAlert: Bool = false
    
    init(viewModel: DeployViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            modeChooseView()
                            modeDesView()
                            nameInputView()
                            symbolInputView()
                            totalSupplyInputView()
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button(action: {
                        if case .ready = viewModel.sendState {
                            isShowAlert = true
                        }
                    }) {
                        HStack(spacing: .margin8) {
                            Text("button.next".localized)
                        }
                    }
                    .disabled(!(viewModel.sendState == .ready || viewModel.sendState == .failed))
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                }
                if case .sending = viewModel.sendState {
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
        .navigationBarTitle("SRC20_Deploy_One_Click_Issu".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("SRC20_Deploy_Confirm".localized(viewModel.mode.title), isPresented: $isShowAlert, actions: {
            HStack{
                Button("button.cancel".localized) {
                    isShowAlert = false
                }
                Button("button.confirm".localized) {
                    
                    viewModel.deploy { sendState in
                        if case .completed = sendState {
                            DispatchQueue.main.async {
                                HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                        
                        if case .failed = sendState {
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
    
    @ViewBuilder private func modeChooseView() -> some View {
        VStack(spacing: .margin16) {
            SectionHeader(text: "SRC20_Deploy_Mode".localized)
            ForEach(DeployType.allCases, id: \.id) { type in
                Button(action: {
                    viewModel.choosed(mode: type)
                }) {
                    HStack(spacing: .margin8) {
                        Image(viewModel.mode == type ?  "checkbox_active_24" : "checkbox_diactive_24")
                        Text(type.title)
                            .themeSubhead2()
                            .fixedSize()
                        Spacer()
                    }
                    
                }
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
    
    @ViewBuilder private func modeDesView() -> some View {
        VStack() {
            HStack(spacing: .margin8) {
                Text(viewModel.mode.des)
                    .themeSubhead2()
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        }
    }
    
    @ViewBuilder private func nameInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Deploy_Name".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.name, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .name)
                
                if !viewModel.name.isEmpty {
                    Button(action: {
                        viewModel.name = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.nameCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.nameCautionState))
        }
    }
    
    @ViewBuilder private func symbolInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Deploy_Symbol".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.symbol, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .symbol)
                
                if !viewModel.symbol.isEmpty {
                    Button(action: {
                        viewModel.symbol = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.symbolCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.symbolCautionState))
        }
    }

    @ViewBuilder private func totalSupplyInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Deploy_Supply".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.totalSupplyString, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .keyboardType(.numberPad)
                    .focused($focusField, equals: .totalSupply)
                
                if !viewModel.totalSupplyString.isEmpty {
                    Button(action: {
                        viewModel.totalSupplyString = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.totalSupplyCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.totalSupplyCautionState))
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
