
import ComponentKit
import Kingfisher
import MarketKit
import SwiftUI
import EvmKit

struct Safe4SwapConfirmationView: View {
    @StateObject private var viewModel: Safe4SwapConfirmationViewModel
    @Binding private var swapPresentationMode: PresentationMode

    @State private var feeSettingsPresented = false

    init(transactionData: TransactionData, tokenIn: Token, tokenOut: Token, amountIn: Decimal, swapPresentationMode: Binding<PresentationMode>) {
        _viewModel = .init(wrappedValue: Safe4SwapConfirmationViewModel(transactionData: transactionData, tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn))
        _swapPresentationMode = swapPresentationMode
    }

    var body: some View {
        ThemeView {
            switch viewModel.state {
            case .quoting:
                VStack(spacing: .margin12) {
                    ProgressView()
                    Text("swap.confirmation.quoting".localized).textSubhead2()
                }
            case let .success(quote):
                quoteView(data: quote)
            case let .failed(error):
                errorView(error: error)
            }
        }
        .navigationTitle("swap.confirmation.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    feeSettingsPresented = true
                }) {
                    Image("manage_2_20").renderingMode(.template)
                }
                .disabled(viewModel.state.isQuoting)
            }
        }
        .onReceive(viewModel.errorSubject) { error in
            HudHelper.instance.showError(subtitle: error)
        }
    }

    @ViewBuilder private func quoteView(data: Safe4SwapConfirmationViewModel.SendData) -> some View {
        VStack {
            ScrollView {
                VStack(spacing: .margin16) {
                    ListSection {
                        tokenRow(title: "swap.you_pay".localized, token: viewModel.tokenIn, amount: viewModel.amountIn, rate: viewModel.rateIn, type: .neutral)
                        tokenRow(title: "swap.you_get".localized, token: viewModel.tokenOut, amount: viewModel.amountIn, rate: viewModel.rateOut, type: .incoming)
                    }
                    ListSection {
                        SendConfirmField.address(title: "send.confirmation.to".localized, value: viewModel.recipient).listRow
                    }

                    if let amountData = viewModel.amountData {
                        ListSection {
                            SendConfirmField.value(title: "fee_settings.network_fee".localized,
                                                   description: .init(title: "fee_settings.network_fee".localized, description: "fee_settings.network_fee.info".localized),
                                                   coinValue: amountData.coinValue,
                                                   currencyValue: amountData.currencyValue,
                                                   formatFull: true
                            ).listRow
                        }
                    }
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }

            if viewModel.quoteTimeLeft > 0 || viewModel.swapping {
                SlideButton(
                    styling: .text(
                        start: "swap.confirmation.slide_to_swap".localized,
                        end: "swap.confirmation.swapping".localized,
                        success: "swap.confirmation.swapped".localized
                    ),
                    action: {
                        try await viewModel.swap()
                    }, completion: {
                        HudHelper.instance.show(banner: .swapped)
                        swapPresentationMode.dismiss()
                    }
                )
                .padding(.vertical, .margin16)
                .padding(.horizontal, .margin16)
            } else {
                Button(action: {
                    viewModel.syncQuote()
                }) {
                    Text("swap.confirmation.refresh".localized)
                }
                .buttonStyle(PrimaryButtonStyle(style: .gray))
                .padding(.vertical, .margin16)
                .padding(.horizontal, .margin16)
            }

            let (bottomText, bottomTextColor) = bottomText()

            Text(bottomText)
                .textSubhead1(color: bottomTextColor)
                .padding(.bottom, .margin8)
        }
    }

    @ViewBuilder private func errorView(error: Error) -> some View {
        VStack {
            ScrollView {
                VStack(spacing: .margin16) {
                    HighlightedTextView(caution: CautionNew(text: error.smartDescription, type: .error))
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }

            Button(action: {
                viewModel.syncQuote()
            }) {
                Text("swap.confirmation.refresh".localized)
            }
            .buttonStyle(PrimaryButtonStyle(style: .gray))
            .padding(.vertical, .margin16)
            .padding(.horizontal, .margin16)

            Text("swap.confirmation.quote_failed".localized)
                .textSubhead1()
                .padding(.bottom, .margin8)
        }
    }

    @ViewBuilder private func tokenRow(title: String, token: Token, amount: Decimal, rate: Decimal?, type: SendConfirmField.AmountType) -> some View {
        let field = SendConfirmField.amount(
            title: title,
            token: token,
            coinValueType: .regular(coinValue: CoinValue(kind: .token(token: token), value: amount)),
            currencyValue: rate.map { CurrencyValue(currency: viewModel.currency, value: amount * $0) },
            type: type
        )

        field.listRow
    }
    
    private func bottomText() -> (String, Color) {
//        if let quote = viewModel.state.quote, !quote.canSwap {
//            return ("swap.confirmation.invalid_quote".localized, .themeGray)
//        } else
        if viewModel.swapping {
            return ("swap.confirmation.please_wait".localized, .themeGray)
        } else if viewModel.quoteTimeLeft > 0 {
            return ("swap.confirmation.quote_expires_in".localized("\(viewModel.quoteTimeLeft)"), .themeJacob)
        } else {
            return ("swap.confirmation.quote_expired".localized, .themeGray)
        }
    }
}

