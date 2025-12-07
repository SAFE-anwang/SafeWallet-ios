import SwiftUI

struct SRC20DestroyView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SRC20DestroyViewModel
    @FocusState private var focusField: SRC20DestroyViewModel.FocusField?
    @FocusState private var isInputActive: Bool
    @State private var presentDestination: PresentDestination?
    @State private var isShowAlert: Bool = false

    init(viewModel: SRC20DestroyViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            tokenInfoView(name: viewModel.token.name, symbol: viewModel.token.symbol, supply: viewModel.totalSupplyString)
                            balanceView(balance: viewModel.balanceString)
                            numberInputView()
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
                    .disabled((viewModel.sendState == .notReady || viewModel.sendState == .sending))
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
        .navigationBarTitle("SRC20_Destroy".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("SRC20_Destroy_Hint".localized, isPresented: $isShowAlert, actions: {
            HStack{
                Button("button.cancel".localized) {
                    isShowAlert = false
                }
                Button("button.confirm".localized) {
                    
                    viewModel.destroy { state in
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
    
    @ViewBuilder private func tokenInfoView(name: String, symbol: String, supply: String) -> some View {
        VStack(spacing: .margin8) {
            Text("SRC20_Edit_Name".localized + " \(name)")
                .themeSubhead1(color: .themeLeah)
            
            Text("SRC20_Edit_Symbol".localized + " \(symbol)")
                .themeSubhead1(color: .themeLeah)
            
            Text("SRC20_Deploy_Supply".localized + ": \(supply)")
                .themeSubhead1(color: .themeLeah)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
    
    @ViewBuilder private func balanceView(balance: String) -> some View {
        VStack() {
            Text("SRC20_Balance".localized + "\(balance)")
                .themeSubhead1(color: .themeLeah)
        }
    }
    
    @ViewBuilder private func numberInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Destroy_Number".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.numberString, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .destroy)

                if !viewModel.numberString.isEmpty {
                    Button(action: {
                        viewModel.numberString = ""
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.amountCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.amountCautionState))
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
