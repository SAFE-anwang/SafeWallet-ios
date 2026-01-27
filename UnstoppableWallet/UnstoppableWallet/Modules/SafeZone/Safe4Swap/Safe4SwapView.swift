import Foundation
import EvmKit
import Kingfisher
import MarketKit
import SwiftUI

struct Safe4SwapView: View {
    @StateObject var viewModel: Safe4SwapViewModel

    @Environment(\.presentationMode) private var presentationMode
    @State private var sendPresented = false
    
    @FocusState var isInputActive: Bool

    init(tokenIn: Token, tokenOut: Token) {
        _viewModel = StateObject(wrappedValue: Safe4SwapViewModel.instance(tokenIn: tokenIn, tokenOut: tokenOut))
    }
    
    init(viewModel: Safe4SwapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            ScrollView {
                VStack(spacing: .margin12) {
                    VStack(spacing: .margin16) {
                        VStack(spacing: .margin8) {
                            amountsView()
                        }
                        buttonView()
                    }
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
        }
        .navigationTitle("swap.safe4.title".localized)
        .navigationDestination(isPresented: $sendPresented) {
                    if let tokenIn = viewModel.tokenIn,
                    let tokenOut = viewModel.tokenOut,
                    let amountIn = viewModel.amountIn,
                     let transactionData = viewModel.transactionData()
                 {
                        Safe4SwapSendView(
                         transactionData: transactionData,
                         tokenIn: tokenIn,
                         tokenOut: tokenOut,
                         amountIn: amountIn,
                         swapPresentationMode: presentationMode
                     )
                 }

            }
            .onChange(of: sendPresented) { presented in
//                    if !presented {
//                        viewModel.autoQuoteIfRequired()
//                    }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("button.cancel".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
    }

    @ViewBuilder private func amountsView() -> some View {
        VStack(spacing: .margin8) {
            boxInView().padding(.horizontal, .margin16)
            boxSeparatorView()
            boxOutView().padding(.horizontal, .margin16)
        }
        .padding(.vertical, 20)
        .modifier(ThemeListStyleModifier(cornerRadius: 18))
    }

    @ViewBuilder private func boxInView() -> some View {
        VStack(spacing: 3) {
            availableBalanceView(value: balanceValueIn())
            HStack(spacing: .margin8) {
                VStack(spacing: 3) {
                    TextField("", text: $viewModel.amountString, prompt: Text("0").foregroundColor(.themeGray))
                        .foregroundColor(.themeLeah)
                        .font(.themeHeadline1)
                        .keyboardType(.decimalPad)
                        .focused($isInputActive)

                    if viewModel.amountIn != nil, viewModel.availableBalanceIn != nil, !viewModel.isAvailableAmountIn {
                        Text("swap.button_error.insufficient_balance".localized)
                            .themeSubhead2(color: .themeRed, alignment: .leading)
                            .frame(height: 20)
                    } else {
                        Text("")
                            .themeBody(color: .themeGray50, alignment: .leading)
                            .frame(height: 20)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if isInputActive {
                            HStack(spacing: 0) {
                                if viewModel.availableBalanceIn != nil {
                                    ForEach(1 ... 4, id: \.self) { multiplier in
                                        let percent = multiplier * 25

                                        Button(action: {
                                            viewModel.setAmountIn(percent: percent)
                                            isInputActive = false
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
                                    isInputActive = false
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

                Spacer()

                selectorButton(token: viewModel.tokenIn) {
                    //
                }
            }
        }
    }

    @ViewBuilder private func boxSeparatorView() -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.themeBlade)
                .frame(height: .heightOneDp)
                .frame(maxWidth: .infinity)

            Button(action: {
                viewModel.interchange()
            }) {
                Image("arrow_medium_2_down_20").renderingMode(.template)
            }
            .buttonStyle(SecondaryCircleButtonStyle(style: .default))

            Rectangle()
                .fill(Color.themeBlade)
                .frame(height: .heightOneDp)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func boxOutView() -> some View {
        VStack(spacing: 3) {
            availableBalanceView(value: balanceValueOut())
            HStack(spacing: .margin8) {
                VStack(spacing: 3) {
                    if let amountOutString = viewModel.amountOutString {
                        Text(amountOutString)
                            .themeHeadline1(color: .themeLeah, alignment: .leading)
                            .lineLimit(1)
                    } else {
                        Text("0").themeHeadline1(color: .themeGray, alignment: .leading)
                    }
                    
                    if viewModel.tokenOut != nil {
                        //
                    } else {
                        Text("\(viewModel.currency.symbol)0")
                            .themeBody(color: .themeGray50, alignment: .leading)
                            .frame(height: 20)
                    }
                }
                
                Spacer()
                selectorButton(token: viewModel.tokenOut) {
                    //
                }
            }
        }
    }

    @ViewBuilder private func selectorButton(token: Token?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: .margin8) {
                CoinIconView(coin: token.map(\.coin))

                if let token {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(token.coin.code).textSubhead1(color: .themeLeah)
                        Text(token.fullBadge).textMicro()
                    }
                } else {
                    Text("swap.select".localized).textSubhead1(color: .themeJacob)
                }

                Image("arrow_small_down_20").themeIcon(color: .themeGray)
            }
        }
    }

    private func color(valueLevel: ValueLevel) -> Color {
        switch valueLevel {
        case .regular: return .themeLeah
        case .warning: return .themeJacob
        case .error: return .themeLucian
        }
    }

    @ViewBuilder private func buttonView() -> some View {
        let (title, style, disabled, showProgress, sendData) = buttonState()

        Button(action: {
            if sendData != nil {
                sendPresented = true
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
        .buttonStyle(PrimaryButtonStyle(style: style))
    }

    @ViewBuilder private func availableBalanceView(value: String?) -> some View {
        HStack(spacing: .margin8) {
            Spacer()
            Text(value ?? "---")
                .textCaption()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, .margin16)
    }

    private func balanceValueIn() -> String? {
        guard let availableBalance = viewModel.availableBalanceIn, let tokenIn = viewModel.tokenIn else {
            return "\("send.available_balance".localized): \(0.00)"
        }
        return "\("send.available_balance".localized): \(availableBalance.safe4FormattedAmount) \(tokenIn.coin.name)"
    }
    
    private func balanceValueOut() -> String? {
        guard let availableBalance = viewModel.availableBalanceOut, let tokenOut = viewModel.tokenOut else {
            return "\("send.available_balance".localized): \(0.00)"
        }
        return "\("send.available_balance".localized): \(availableBalance.safe4FormattedAmount) \(tokenOut.coin.name)"
    }

    private func buttonState() -> (String, PrimaryButtonStyle.Style, Bool, Bool, TransactionData?) {
        let title: String
        let style: PrimaryButtonStyle.Style = .yellow
        var disabled = true
        var showProgress = false
        let sendData: TransactionData? = viewModel.transactionData()
        
        if viewModel.tokenIn == nil {
            title = "swap.select_token_in".localized
        } else if viewModel.tokenOut == nil {
            title = "swap.select_token_out".localized
        } else if viewModel.amountIn == nil {
            title = "swap.enter_amount".localized
        } else if viewModel.adapterState == nil {
            title = "swap.token_not_enabled".localized
        } else if let adapterState = viewModel.adapterState, adapterState.syncing {
            title = "swap.token_syncing".localized
            showProgress = true
        } else if let adapterState = viewModel.adapterState, !adapterState.isSynced {
            title = "swap.token_not_synced".localized
        } else if let availableBalance = viewModel.availableBalanceIn, let amountIn = viewModel.amountIn, amountIn > availableBalance {
            title = "swap.insufficient_balance".localized
        } else if sendData == nil {
            title = "swap.trade_error.not_found".localized
        } else {
            title = "swap.proceed_button".localized
            disabled = false
        }

        return (title, style, disabled, showProgress, sendData)
    }
    
    struct CoinIconView: View {
        let coin: Coin?
        let placeholderImage: Image?

        init(coin: Coin?, placeholderImage: Image? = nil) {
            self.coin = coin
            self.placeholderImage = placeholderImage
        }

        var body: some View {
            icon(coin.flatMap { URL(string: $0.imageUrl) })
                .clipShape(Circle())
                .frame(width: .iconSize32, height: .iconSize32)
        }

        @ViewBuilder func icon(_ url: URL?) -> some KFImageProtocol {
            KFImage.url(url)
                .resizable()
                .placeholder {
                    if let placeholderImage {
                        placeholderImage
                    } else {
                        Circle().fill(Color.themeSteel)
                    }
                }
        }
    }
}


