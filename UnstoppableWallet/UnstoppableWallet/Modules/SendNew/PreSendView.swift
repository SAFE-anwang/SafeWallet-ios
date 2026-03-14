
import Kingfisher
import SwiftUI

struct PreSendView: View {
    @StateObject var viewModel: PreSendViewModel
    private let addressVisible: Bool
    private let onDismiss: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var focusField: FocusField?

    @Binding var path: NavigationPath

    init(wallet: Wallet, handler: IPreSendHandler?, resolvedAddress: ResolvedAddress, amount: Decimal? = nil, memo: String? = nil, addressVisible: Bool = true, path: Binding<NavigationPath>, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: PreSendViewModel(wallet: wallet, handler: handler, resolvedAddress: resolvedAddress, amount: amount, memo: memo))
        self.addressVisible = addressVisible
        _path = path
        self.onDismiss = onDismiss
    }

    var body: some View {
        ThemeView {
//<<<<<<< HEAD
//            ScrollView {
//                VStack(spacing: .margin16) {
//                    if addressVisible {
//                        if viewModel.resolvedAddress.issueTypes.isEmpty {
//                            addressView()
//                        } else {
//                            addressView()
//                                .overlay(RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
//                                .stroke(Color.themeRed50, lineWidth: .heightOneDp))
//                        }
//                    }
//
//                    VStack(spacing: .margin8) {
//                        inputView()
//                        availableBalanceView(value: balanceValue())
//                    }
//                    
//                    if viewModel.isSupportedTimeLockToken {
//                        VStack(spacing: .margin8) {
//                            lockTimeView()
//                        }
//                    }
//
//                    if viewModel.hasMemo {
//                        memoView()
//                    }
//
//                    buttonView()
//
//                    if !viewModel.cautions.isEmpty {
//                        cautionsView()
//                    }
//                }
//                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
//                .animation(.linear, value: viewModel.hasMemo)
//            }
//        }
//        .navigationTitle(viewModel.title)
//        .navigationBarTitleDisplayMode(.inline)
//        .navigationDestination(isPresented: $confirmPresented) {
//            if let sendData = viewModel.sendData {
//                RegularSendView(sendData: sendData.sendData, address: sendData.address) {
//                    HudHelper.instance.show(banner: .sent)
//                    onDismiss()
//                }
//                .toolbarRole(.editor)
//            }
//        }
//=======
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin16) {
                        if addressVisible {
                            if viewModel.resolvedAddress.issueTypes.isEmpty {
                                addressView()
                            } else {
                                addressView()
                                    .overlay(RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous).stroke(Color.themeRed50, lineWidth: .heightOneDp))
                            }
                        }

                        VStack(spacing: .margin8) {
                            inputView()
                            availableBalanceView(value: balanceValue())
                        }
                        
                        if viewModel.isSupportedTimeLockToken {
                            VStack(spacing: .margin8) {
                                lockTimeView()
                            }
                        }

                        if viewModel.hasMemo {
                            memoView()
                        }

                        if !viewModel.cautions.isEmpty {
                            cautionsView()
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    .animation(.linear, value: viewModel.hasMemo)
                }
                .onTapGesture {
                    focusField = nil
                }
            } bottomContent: {
                buttonView()
            } keyboardContent: {
                AmountAccessoryView(
                    visible: focusField != nil,
                    hasPercents: viewModel.availableBalance != nil,
                    onPercent: { percent in
                        viewModel.setAmountIn(percent: percent)
                        focusField = nil
                    },
                    onTrash: {
                        viewModel.clearAmountIn()
                    }
                )
            }
            .animation(.easeOut(duration: 0.25), value: focusField)
        }
        .onFirstAppear {
            focusField = .amount
        }
        .navigationDestination(for: ConfirmationData.self) { data in
            RegularSendView(sendData: data.sendData, address: data.address) {
                HudHelper.instance.show(banner: .sent)
                onDismiss()
            }
            .toolbarRole(.editor)
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
//>>>>>>> master
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let handler = viewModel.handler, handler.hasSettings {
                    Button(action: {
                        if let handler = viewModel.handler {
                            Coordinator.shared.present { _ in
                                handler.settingsView {
                                    viewModel.syncSendData()
                                }
                            }
                        }
                    }) {
                        Image("settings_24")
                            .renderingMode(.template)
                            .foregroundColor(handler.settingsModified ? .themeJacob : .themeGray)
                            .dotOverlay(visible: handler.settingsModified)
                    }
                }
            }
        }
        .toolbarRole(.editor)
        .accentColor(.themeJacob)
    }

    @ViewBuilder private func availableBalanceView(value: String?) -> some View {
        HStack(spacing: .margin8) {
            Text("send.available_balance".localized).textCaption()
            Spacer()
            Text(value ?? "---")
                .textCaption()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, .margin16)
    }

    @ViewBuilder private func inputView() -> some View {
        VStack(spacing: 3) {
            TextField("", text: $viewModel.amountString, prompt: Text("0").foregroundColor(.themeGray))
                .foregroundColor(.themeLeah)
                .font(.themeHeadline1)
                .tint(.themeInputFieldTintColor)
                .keyboardType(.decimalPad)
                .focused($focusField, equals: .amount)

            if let coinPrice = viewModel.coinPrice {
                HStack(spacing: 0) {
                    Text(viewModel.currency.symbol).textBody(color: .themeGray)

                    TextField("", text: $viewModel.fiatAmountString, prompt: Text("0").foregroundColor(.themeGray))
                        .foregroundColor(.themeGray)
                        .font(.themeBody)
                        .tint(.themeInputFieldTintColor)
                        .keyboardType(.decimalPad)
                        .focused($focusField, equals: .fiatAmount)
                        .frame(height: 20)
                        .disabled(coinPrice.expired)
                }
            } else {
                Text("swap.rate_not_available".localized)
                    .themeSubhead2(color: .themeGray50, alignment: .leading)
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, 20)
        .modifier(ThemeListStyleModifier(cornerRadius: 18))
//<<<<<<< HEAD
//        .onFirstAppear {
//            focusField = .amount
//        }
//        .toolbar {
//            ToolbarItemGroup(placement: .keyboard) {
//                if focusField != nil {
//                    HStack(spacing: 0) {
//                        if viewModel.availableBalance != nil {
//                            ForEach(1 ... 4, id: \.self) { multiplier in
//                                let percent = multiplier * 25
//
//                                Button(action: {
//                                    viewModel.setAmountIn(percent: percent)
//                                    focusField = nil
//                                }) {
//                                    Text("\(percent)%").textSubhead1(color: .themeLeah)
//                                }
//                                .frame(maxWidth: .infinity)
//
//                                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
//                                    .fill(Color.themeBlade)
//                                    .frame(width: 1)
//                                    .frame(maxHeight: .infinity)
//                            }
//                        } else {
//                            Spacer()
//                        }
//
//                        Button(action: {
//                            viewModel.clearAmountIn()
//                        }) {
//                            Image(systemName: "trash")
//                                .font(.themeSubhead1)
//                                .foregroundColor(.themeLeah)
//                        }
//                        .frame(maxWidth: .infinity)
//
//                        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
//                            .fill(Color.themeBlade)
//                            .frame(width: 1)
//                            .frame(maxHeight: .infinity)
//
//                        Button(action: {
//                            focusField = nil
//                        }) {
//                            Image(systemName: "keyboard.chevron.compact.down")
//                                .font(.themeSubhead1)
//                                .foregroundColor(.themeLeah)
//                        }
//                        .frame(maxWidth: .infinity)
//                    }
//                    .padding(.horizontal, -16)
//                    .frame(maxWidth: .infinity)
//                }
//            }
//        }
//=======
//>>>>>>> master
    }

    @ViewBuilder private func addressView() -> some View {
        ListSection {
            ClickableRow {
                presentationMode.wrappedValue.dismiss()
            } content: {
                Text("send.confirmation.to".localized).textSubhead2()

                Text(viewModel.resolvedAddress.address)
                    .textSubhead2(color: .themeLeah)
                    .multilineTextAlignment(.leading)

                Spacer()

                if !viewModel.resolvedAddress.issueTypes.isEmpty {
                    Image.warningIcon
                }

                Image("arrow_small_down_20").themeIcon()
            }
        }
    }

    @ViewBuilder private func memoView() -> some View {
        InputTextRow {
            InputTextView(
                placeholder: "send.confirmation.memo_placeholder".localized,
                multiline: true,
                font: .themeBody.italic(),
                text: $viewModel.memo
            )
        }
    }

    @ViewBuilder private func buttonView() -> some View {
        let (title, disabled, showProgress) = buttonState()

        Button(action: {
//<<<<<<< HEAD
//            if let step = viewModel.allowanceHandler.allowanceState?.customButtonState?.preSwapStep, let amount = viewModel.amount {
//                Coordinator.shared.present { isPresented in
//                    viewModel.allowanceHandler.preSwapView(step: step, amount: amount, isPresented: isPresented) {
//                        viewModel.syncSendData()
//                        isPresented.wrappedValue = false
//                    }
//                }
//            }else if viewModel.resolvedAddress.issueTypes.isEmpty {
//                confirmPresented = true
//            } else {
//                Coordinator.shared.present(type: .bottomSheet) { isPresented in
//                    BottomSheetView(
//                        icon: .local(name: "warning_2_24", tint: .themeLucian),
//                        title: "send.address.risky.title".localized,
//                        items: [
//                            .highlightedDescription(text: "send.address.risky.description".localized, style: .alert),
//                        ],
//                        buttons: [
//                            .init(style: .red, title: "send.continue_anyway".localized) {
//                                isPresented.wrappedValue = false
//                                confirmPresented = true
//                            },
//                            .init(style: .transparent, title: "button.cancel".localized) { isPresented.wrappedValue = false },
//                        ],
//                        isPresented: isPresented
//=======
            guard let sendData = viewModel.sendData else { return }
            let proceedToSend = {
                if #available(iOS 17.0, *) {
                    focusField = nil
                    path.append(ConfirmationData(
                        sendData: sendData.sendData,
                        address: sendData.address
                    ))
                } else {
                    presentRegularSendView(sendData: sendData.sendData, address: sendData.address)
                }
            }
            if viewModel.resolvedAddress.issueTypes.isEmpty {
                proceedToSend()
            } else {
                Coordinator.shared.present(type: .bottomSheet) { isPresented in
                    BottomSheetView(
                        items: [
                            .title(icon: nil, title: "send.address.risky.title".localized),
                            .warning(text: "send.address.risky.description".localized),
                            .buttonGroup(.init(buttons: [
                                .init(style: .red, title: "send.continue_anyway".localized) {
                                    isPresented.wrappedValue = false
                                    proceedToSend()
                                },
                                .init(style: .transparent, title: "button.cancel".localized) { isPresented.wrappedValue = false },
                            ])),
                        ],
//>>>>>>> master
                    )
                }
            }
        }) {
            HStack(spacing: .margin8) {
                if showProgress {
                    ProgressView()
                }

                Text(title)
            }
        }
        .disabled(disabled)
        .buttonStyle(PrimaryButtonStyle(style: .yellow))
    }

    private func presentRegularSendView(sendData: SendData, address: String?) {
        Coordinator.shared.present { regularSendPresented in
            RegularSendViewWrapper(
                sendData: sendData,
                address: address,
                isPresented: regularSendPresented,
                onSuccess: {
                    HudHelper.instance.show(banner: .sent)
                    onDismiss()
                }
            )
        }
    }

    @ViewBuilder private func cautionsView() -> some View {
        let cautions = viewModel.cautions

        VStack(spacing: .margin12) {
            ForEach(cautions.indices, id: \.self) { index in
                HighlightedTextView(caution: cautions[index])
            }
        }
    }
    
    @ViewBuilder private func lockTimeView() -> some View {
        VStack(spacing: .margin8) {
            HStack(spacing: .margin4) {
                Button(action: {
                    Coordinator.shared.present(type: .alert) { isPresented in
                        OptionAlertView(
                            title: "send.hodler_locktime".localized,
                            viewItems: viewModel.timeLockItems.map{AlertViewItem(text: $0.title, selected: $0.days == viewModel.selectedTimeLock.days) },
                            onSelect: { index in
                                viewModel.selectedTimeLock = viewModel.timeLockItems[index]
                            },
                            isPresented: isPresented
                        )
                    }
                }){
                    HStack(spacing: .margin8) {
                        Text("send.hodler_locktime".localized).themeSubhead2()
                        Spacer()
                        HStack(spacing: .margin8) {
                            Text(viewModel.selectedTimeLock.title).themeSubhead2()
                            Image("arrow_small_down_20").themeIcon()
                        }
                        .fixedSize()
                    }
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin12, trailing: .margin16))
            .background(RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous).fill(Color.themeLawrence))
            
            Text("时间锁（TimeLock）只适用于发送 SAFE（从 1 开始）".localized)
                .themeCaption(alignment: .leading)
                .multilineTextAlignment(.trailing)
        }

    }

    private func balanceValue() -> String? {
        guard let availableBalance = viewModel.availableBalance else {
            return nil
        }

        return AppValue(token: viewModel.token, value: availableBalance).formattedFull()
    }
    private func buttonState() -> (String, Bool, Bool) {
        let title: String
        var disabled = true
        var showProgress = false

        if viewModel.adapterState == nil {
            title = "send.token_not_enabled".localized
        } else if let adapterState = viewModel.adapterState, adapterState.syncing {
            title = "send.token_syncing".localized
            showProgress = true
        } else if let adapterState = viewModel.adapterState, !adapterState.isSynced {
            title = "send.token_not_synced".localized
        } else if viewModel.amount == nil {
            title = "send.enter_amount".localized
        } else if let availableBalance = viewModel.availableBalance, let amount = viewModel.amount, amount > availableBalance {
            title = "send.insufficient_balance".localized
//<<<<<<< HEAD
        } else if let amount = viewModel.amount, viewModel.selectedTimeLock != .none, amount < viewModel.minTimeLockCoinValue {
            title = "最小锁定数为 \(viewModel.minTimeLockCoinValue)".localized
//        } else if viewModel.allowanceHandler.allowanceSyncing == true {
//            title = ""
//            showProgress = true
//        } else if viewModel.allowanceHandler.isApproving == true {
//            title = "审批中"
//            showProgress = true
        } else if let state = viewModel.allowanceHandler.allowanceState, let buttonState = state.customButtonState {
            if case .allowed = state {
                title = "send.next_button".localized
                disabled = viewModel.sendData == nil
            }else {
                title = buttonState.title
                disabled = buttonState.disabled
                showProgress = buttonState.showProgress
            }
//=======
//>>>>>>> master
        } else {
            title = "send.next_button".localized
            disabled = viewModel.sendData == nil
        }

        return (title, disabled, showProgress)
    }
}

extension PreSendView {
    private enum FocusField: Int, Hashable {
        case amount
        case fiatAmount
    }

    struct ConfirmationData: Hashable, Equatable {
        let id = UUID()
        let sendData: SendData
        let address: String?

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }
}
