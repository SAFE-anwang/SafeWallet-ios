import SwiftUI

struct SafeLineLockView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.addressParserFilter) private var parserFilter
    @StateObject var viewModel: SafeLineLockViewModel
    @FocusState private var focusField: SafeLineLockViewModel.FocusField?
    @FocusState private var isInputActive: Bool
    @State private var dateText = ""
    @State private var presentDestination: PresentDestination?
    
    init(viewModel: SafeLineLockViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var borderColor: Color {
        switch viewModel.addressResult {
        case .invalid: return .themeLucian
        default: return .themeBlade
        }
    }
    
    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            balanceView()
                            addressInputView()
                            inputView()
                            lockNumView()
                            startDateView()
                            intervalMonthView()
                            if let des = viewModel.lockDes {
                                Text(des)
                                    .themeSubhead1(color: .themeLeah)
                            }
                            
                            if let tips = viewModel.lockTips {
                                Text(tips)
                                    .themeSubhead1(color: .themeLucian)
                            }
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button(action: {
                        if case let .ready(data) = viewModel.sendState {
                            do {
                                let info = SendEvmData.SendInfo(domain: data.to.eip55)
                                let sendData = SendEvmData(transactionData: data, additionalInfo: .send(info: info), warnings: [])
                                let evmKitWrapper = try Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper(account: viewModel.account, blockchainType: .safe4)
                                if let vc = SendEvmConfirmationModule.viewController(evmKitWrapper: evmKitWrapper, sendData: sendData) {
                                    DispatchQueue.main.async { [self] in
                                        presentDestination = .toConfirmation(vc: vc)
                                    }
                                }
                            }catch{}
                        }
                    }) {
                        HStack(spacing: .margin8) {
                            Text("button.next".localized)
                        }
                    }
                    .disabled(viewModel.sendDisabled)
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
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
            .navigationBarTitle("safe_zone.row.linear".localized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $presentDestination, onDismiss: {
                DispatchQueue.main.async {
                    HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                    presentationMode.wrappedValue.dismiss()
                }
            }) { present in
                switch present {
                case let .toConfirmation(vc):
                    SendEvmConfirmationView(viewController: vc)
                }
            }
        }
    }

    
    @ViewBuilder private func balanceView() -> some View {
        ThemeView {
            HStack {
                Text("send.available_balance".localized)
                    .themeSubhead2()
                if let balance = viewModel.availableBalance {
                    Text( "\(balance.safe4FormattedAmount)" + " " + "SAFE")
                        .themeSubhead2(color: .themeLeah, alignment: .trailing)
                }else {
                    Text("N/A" + "SAFE")
                        .themeSubhead2(color: .themeLeah, alignment: .trailing)
                }
                
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin12, trailing: .margin16))
            .modifier(ThemeListStyleModifier(themeListStyle: .bordered, cornerRadius: 14))

        }
    }
    
    @ViewBuilder func addressInputView() -> some View {
        AddressViewNew(
            initial: .init(
                blockchainType: viewModel.token.blockchainType,
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
    
    @ViewBuilder private func inputView() -> some View {
        VStack() {
            SectionHeader(text: "safe_lock.amount.unlock".localized)
            VStack(spacing: 3) {
                HStack(spacing: .margin8) {
                    TextField("", text: $viewModel.amountString, prompt: Text("0").foregroundColor(.themeGray))
                        .foregroundColor(.themeLeah)
                        .font(.themeHeadline1)
                        .keyboardType(.decimalPad)
                        .focused($focusField, equals: .amount)
                    
                    if viewModel.amountString.isEmpty {
                        Button(action: {
                            viewModel.maxAmountIn()
                        }, label: {
                            Text("send.max_button".localized)
                        })
                        .buttonStyle(SecondaryButtonStyle(style: .default))
                    }else {
                        Button(action: {
                            viewModel.clearAmountIn()
                        }, label: {
                            Image("trash_20").renderingMode(.template)
                        })
                        .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                    }

                }
                if viewModel.rate != nil {
                    HStack(spacing: 0) {
                        Text(viewModel.currency.symbol).textBody(color: .themeGray)

                        TextField("", text: $viewModel.fiatAmountString, prompt: Text("0").foregroundColor(.themeGray))
                            .foregroundColor(.themeGray)
                            .font(.themeBody)
                            .keyboardType(.decimalPad)
                            .focused($focusField, equals: .fiatAmount)
                            .frame(height: 20)
                    }
                } else {
                    Text("swap.rate_not_available".localized)
                        .themeSubhead2(color: .themeGray50, alignment: .leading)
                        .frame(height: 20)
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin12)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.amountCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.amountCautionState))
        }
    }
    
    @ViewBuilder private func lockNumView() -> some View {
        VStack() {
            SectionHeader(text: "safe_zone.lock_times".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.lockNumString, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .keyboardType(.numberPad)
                    .focused($focusField, equals: .amount)
                
                if !viewModel.lockNumString.isEmpty {
                    Button(action: {
                        viewModel.clearLockNum()
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.lockNumCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.lockNumCautionState))
        }
    }
    
    @ViewBuilder private func startDateView() -> some View {
        VStack() {
            SectionHeader(text: "safe_lock.month.start".localized)
            DatePickerTextField(
                date: $viewModel.startDate,
                placeholder: "Select date"
            ).frame(height: 50)
        }
    }
    
    @ViewBuilder private func intervalMonthView() -> some View {
        VStack() {
            SectionHeader(text: "safe_lock.month.interval".localized)
            HStack(spacing: .margin8) {
                TextField("", text: $viewModel.intervalMonthString, prompt: Text("").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .keyboardType(.numberPad)
                    .focused($focusField, equals: .amount)
                
                if !viewModel.intervalMonthString.isEmpty {
                    Button(action: {
                        viewModel.clearIntervalMonth()
                    }, label: {
                        Image("trash_20").renderingMode(.template)
                    })
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.intervalMonthCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.intervalMonthCautionState))
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

extension SafeLineLockView {
    enum PresentDestination: Hashable, Identifiable {
        case toConfirmation(vc: UIViewController)
        
        var id: Self {
            self
        }
    }
}
struct DatePickerTextField: UIViewRepresentable {
    @Binding var date: Date
    var placeholder: String
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        
        let datePicker = UIDatePicker()
        datePicker.minimumDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.backgroundColor = .themeTyler
        datePicker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.dateChanged(_:)),
            for: .valueChanged
        )
        
        textField.inputView = datePicker
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.dismissPicker))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.setItems([flexibleSpace, doneButton], animated: true)
        textField.inputAccessoryView = toolbar
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = date.formatted(date: .abbreviated, time: .omitted)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(date: $date)
    }
    
    class Coordinator: NSObject {
        @Binding var date: Date
        
        init(date: Binding<Date>) {
            self._date = date
        }
        
        @objc func dateChanged(_ sender: UIDatePicker) {
            date = sender.date
        }
        
        @objc func dismissPicker() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}
