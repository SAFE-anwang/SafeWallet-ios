import Kingfisher
import SwiftUI

struct CrossPreSendView: View {
    @StateObject var viewModel: CrossPreSendViewModel

    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.addressParserFilter) private var parserFilter
    @FocusState private var focusField: FocusField?
    @State private var confirmPresented = false
    @Binding private var isPresented: Bool

    init(viewModel: CrossPreSendViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ScrollView {
                    VStack(spacing: .margin16) {
                        balanceView()
                        inputView()
                        
                        VStack(spacing: .margin8) {
                            addressInputView()
                        }
                        
                        if viewModel.hasMemo {
                            memoView()
                        }
                        
                        buttonView()
                        
                        if !viewModel.cautions.isEmpty {
                            cautionsView()
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    .animation(.linear, value: viewModel.hasMemo)
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $confirmPresented) {
                if let sendData = viewModel.sendData {
                    RegularSendView(sendData: sendData.sendData, address: sendData.address) {
                        HudHelper.instance.show(banner: .sent)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .toolbarRole(.editor)
                }
            }
            .toolbarRole(.editor)
            .accentColor(.themeJacob)
        }
    }
    
    @ViewBuilder private func balanceView() -> some View {
        ThemeView {
            HStack {
                Text("send.available_balance".localized)
                    .themeSubhead2()
                if let balance = viewModel.availableBalance {
                    Text( "\(balance.safe4FormattedAmount) \(viewModel.token.coin.code)" )
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
        Text("safe_zone.send.receiver".localized)
            .themeSubhead1(alignment: .leading)
        AddressViewNew(
            initial: .init(
                blockchainType: viewModel.token.blockchainType,
                showContacts: true
            ),
            text: $viewModel.address,
            result: $viewModel.addressResult,
            parserFilter: parserFilter,
            borderColor: Binding(get: { viewModel.borderColor }, set: { _ in })
        )
        .modifier(CautionBorder(cautionState: $viewModel.addressCautionState))
        .modifier(CautionPrompt(cautionState: $viewModel.addressCautionState))
    }

    @ViewBuilder private func inputView() -> some View {
        VStack(spacing: 3) {
            TextField("", text: $viewModel.amountString, prompt: Text("0").foregroundColor(.themeGray))
                .foregroundColor(.themeLeah)
                .font(.themeHeadline1)
                .keyboardType(.decimalPad)
                .focused($focusField, equals: .amount)

            if let coinPrice = viewModel.coinPrice {
                HStack(spacing: 0) {
                    Text(viewModel.currency.symbol).textBody(color: .themeGray)

                    TextField("", text: $viewModel.fiatAmountString, prompt: Text("0").foregroundColor(.themeGray))
                        .foregroundColor(.themeGray)
                        .font(.themeBody)
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
        .onFirstAppear {
            focusField = .amount
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusField != nil {
                    HStack(spacing: 0) {
                        if viewModel.availableBalance != nil {
                            ForEach(1 ... 4, id: \.self) { multiplier in
                                let percent = multiplier * 25

                                Button(action: {
                                    viewModel.setAmountIn(percent: percent)
                                    focusField = nil
                                }) {
                                    Text("\(percent)%").textSubhead1(color: .themeLeah)
                                }
                                .frame(maxWidth: .infinity)

                                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                                    .fill(Color.themeBlade)
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        } else {
                            Spacer()
                        }

                        Button(action: {
                            viewModel.clearAmountIn()
                        }) {
                            Image(systemName: "trash")
                                .font(.themeSubhead1)
                                .foregroundColor(.themeLeah)
                        }
                        .frame(maxWidth: .infinity)

                        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                            .fill(Color.themeBlade)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        Button(action: {
                            focusField = nil
                        }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.themeSubhead1)
                                .foregroundColor(.themeLeah)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, -16)
                    .frame(maxWidth: .infinity)
                }
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
            if viewModel.resolvedAddress.issueTypes.isEmpty {
                confirmPresented = true
            } else {
                Coordinator.shared.present(type: .bottomSheet) { isPresented in
                    BottomSheetView(
                        items: [
                            .title(icon: nil, title: "send.address.risky.title".localized),
                            .text(text: "send.address.risky.description".localized),
                            .buttonGroup(.init(buttons: [
                                .init(style: .red, title: "send.continue_anyway".localized) {
                                    isPresented.wrappedValue = false
                                    confirmPresented = true
                                },
                                .init(style: .transparent, title: "button.cancel".localized) { isPresented.wrappedValue = false },
                                ],
                                alignment: .horizontal)),
                        ],
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

    @ViewBuilder private func cautionsView() -> some View {
        let cautions = viewModel.cautions

        VStack(spacing: .margin12) {
            ForEach(cautions.indices, id: \.self) { index in
                HighlightedTextView(caution: cautions[index])
            }
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
        } else if let amount = viewModel.amount, amount < viewModel.crossChainHandler.minAmount {
            title = "send.amount_error.minimum_amount".localized("\(viewModel.crossChainHandler.minAmount)")
        } else if let availableBalance = viewModel.availableBalance, let amount = viewModel.amount, amount > availableBalance {
            title = "send.insufficient_balance".localized
        } else {
            title = "send.next_button".localized
            disabled = viewModel.sendData == nil
        }

        return (title, disabled, showProgress)
    }
}

extension CrossPreSendView {
    private enum FocusField: Int, Hashable {
        case amount
        case fiatAmount
    }
}
