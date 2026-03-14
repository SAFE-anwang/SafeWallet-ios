import SwiftUI

struct SRC20AdditionalView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.addressParserFilter) private var parserFilter
    @StateObject var viewModel: SRC20AdditionalViewModel
    @FocusState private var focusField: SRC20AdditionalViewModel.FocusField?
    @State private var isShowAlert: Bool = false

    init(viewModel: SRC20AdditionalViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var borderColor: Color {
        switch viewModel.addressResult {
        case .invalid: return .themeLucian
        default: return .themeBlade
        }
    }
    
    var body: some View {
        ThemeView {
            ZStack{
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            tokenInfoView(name: viewModel.token.name, symbol: viewModel.token.symbol, supply: viewModel.totalSupplyString)
                            addressInputView()
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
        .navigationBarTitle("SRC20_Issuance".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("SRC20_Additional_Hint".localized, isPresented: $isShowAlert, actions: {
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
    @ViewBuilder func addressInputView() -> some View {
        SectionHeader(text: "SRC20_Additional_Address".localized)
        AddressViewNew(
            initial: .init(
                blockchainType: .safe4,
                showContacts: true
            ),
            text: $viewModel.address,
            result: $viewModel.addressResult,
            parserFilter: parserFilter,
            borderColor: Binding(get: { borderColor }, set: { _ in })
        )
        .modifier(CautionBorder(cautionState: $viewModel.addressCautionState))
        .modifier(CautionPrompt(cautionState: $viewModel.addressCautionState))
    }

    @ViewBuilder private func numberInputView() -> some View {
        VStack() {
            SectionHeader(text: "SRC20_Additional_Number".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.numberString, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .focused($focusField, equals: .number)

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
