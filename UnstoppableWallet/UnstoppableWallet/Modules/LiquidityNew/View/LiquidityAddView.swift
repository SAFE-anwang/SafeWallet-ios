import Foundation
import Kingfisher
import MarketKit
import SwiftUI

struct LiquidityAddView: View {
    @StateObject var viewModel: LiquidityAddViewModel
    private let onFinish: (() -> Void)?
    @Environment(\.presentationMode) private var presentationMode
    @State private var sendPresented = false
    @FocusState var isInputActive: Bool
    @FocusState private var isV3LowestPriceInputActive: Bool
    @FocusState private var isV3HighestPriceInputActive: Bool

    @State private var shouldPresentTokenIn: Bool
    @State private var v3LowestPriceInput: String = ""
    @State private var v3HighestPriceInput: String = ""

    init(token: Token? = nil, onFinish: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: LiquidityAddViewModel.instance(token: token))
        shouldPresentTokenIn = token == nil
        self.onFinish = onFinish
    }

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 8) {
                            amountsView()

                            if viewModel.currentQuote == nil {
                                availableBalanceView(valueIn: balanceValue(), valueOut: balanceValueOut())
                            }
                            if viewModel.v3Enabled {
                                v3RangeView()
                            }
                        }

                        if let currentQuote = viewModel.currentQuote {
                            quoteView(quote: currentQuote)
                            quoteCautionsView(quote: currentQuote)
                        }
                    }
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
                }
                .onTapGesture {
                    isInputActive = false
                }
            } bottomContent: {
                buttonView()
            } keyboardContent: {
                AmountAccessoryView(
                    visible: isInputActive,
                    hasPercents: viewModel.availableBalance != nil,
                    onPercent: { percent in
                        viewModel.setAmountIn(percent: percent)
                        isInputActive = false
                    },
                    onTrash: {
                        viewModel.clearAmountIn()
                    }
                )
            }
            .animation(.easeOut(duration: 0.25), value: isInputActive)
        }
        .onAppear {
            viewModel.autoQuoteIfRequired()
            v3LowestPriceInput = viewModel.v3LowestPrice ?? ""
            v3HighestPriceInput = viewModel.v3HighestPrice ?? ""
        }
        .onChange(of: viewModel.v3LowestPrice) { newValue in
            v3LowestPriceInput = newValue ?? ""
        }
        .onChange(of: viewModel.v3HighestPrice) { newValue in
            v3HighestPriceInput = newValue ?? ""
        }
        .onDisappear {
            viewModel.stopAutoQuoting()
        }
        .navigationDestination(isPresented: $sendPresented) {
            if let tokenIn = viewModel.tokenIn,
               let tokenOut = viewModel.tokenOut,
               let amountIn = viewModel.amountIn,
               let provider = viewModel.proceedProvider,
               let amountOut = viewModel.proceedAmountOut
            {
                LiquidityAddSendView(
                    token0: tokenIn,
                    token1: tokenOut,
                    amount0: amountIn,
                    amount1: amountOut,
                    provider: provider,
                    v3TickType: viewModel.currentV3TickType,
                    manualAmountOutMode: viewModel.isSafeSwapManualAmountOutMode,
                    onFinish: onFinish ?? {
                        viewModel.reset()
                        sendPresented = false
                    })
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
        HStack(spacing: .margin8) {
            VStack(spacing: 3) {
                TextField("", text: $viewModel.amountString, prompt: Text("0").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline1)
                    .keyboardType(.decimalPad)
                    .focused($isInputActive)

                if viewModel.tokenIn != nil {
                    if let coinPriceIn = viewModel.coinPriceIn {
                        HStack(spacing: 0) {
                            Text(viewModel.currency.symbol).textBody(color: .themeGray)

                            TextField("", text: $viewModel.fiatAmountString, prompt: Text("0").foregroundColor(.themeGray))
                                .foregroundColor(.themeGray)
                                .font(.themeBody)
                                .keyboardType(.decimalPad)
                                .focused($isInputActive)
                                .frame(height: 20)
                                .disabled(coinPriceIn.expired)
                        }
                    } else {
                        Text("swap.rate_not_available".localized)
                            .themeSubhead2(color: .themeGray50, alignment: .leading)
                            .frame(height: 20)
                    }
                } else {
                    Text("\(viewModel.currency.symbol)0")
                        .themeBody(color: .themeGray50, alignment: .leading)
                        .frame(height: 20)
                }
            }

            Spacer()

            selectorButton(token: viewModel.tokenIn) {
                presentTokenIn()
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
        HStack(spacing: .margin8) {
            VStack(spacing: 3) {
                if viewModel.currentQuote == nil {
                    if viewModel.isSafeSwapManualAmountOutMode {
                        TextField("", text: $viewModel.manualAmountOutString, prompt: Text("0").foregroundColor(.themeGray))
                            .foregroundColor(.themeLeah)
                            .font(.themeHeadline1)
                            .keyboardType(.decimalPad)
                            .focused($isInputActive)
                    } else {
                        Text("0").themeHeadline1(color: .themeGray, alignment: .leading)
                    }
                } else {
                    if let amountOutString = viewModel.amountOutString {
                        Text(amountOutString)
                            .themeHeadline1(color: .themeLeah, alignment: .leading)
                            .lineLimit(1)
                    } else {
                        Text("0").themeHeadline1(color: .themeGray, alignment: .leading)
                    }
                }

                if viewModel.tokenOut != nil {
                    if viewModel.rateOut != nil {
                        HStack(spacing: .margin8) {
                            Text("\(viewModel.currency.symbol)\((viewModel.fiatAmountOut ?? 0).description)")
                                .textBody(color: .themeGray)
                                .frame(height: 20)

                            if let priceImpact = viewModel.priceImpact, priceImpact < 0 {
                                let level = LiquidityAddViewModel.PriceImpactLevel(priceImpact: abs(priceImpact))

                                switch level {
                                case .negligible:
                                    EmptyView()
                                default:
                                    Text("(\(priceImpact.rounded(decimal: 2).description)%)")
                                        .textSubhead1(color: color(valueLevel: level.valueLevel))
                                }
                            }

                            Spacer()
                        }
                    } else {
                        Text("swap.rate_not_available".localized)
                            .themeSubhead2(color: .themeGray50, alignment: .leading)
                            .frame(height: 20)
                    }
                } else {
                    Text("\(viewModel.currency.symbol)0")
                        .themeBody(color: .themeGray50, alignment: .leading)
                        .frame(height: 20)
                }
            }

            Spacer()

            selectorButton(token: viewModel.tokenOut) {
                Coordinator.shared.present { isPresented in
                    MultiSwapTokenSelectView(
                        title: "swap.you_get".localized,
                        currentToken: $viewModel.tokenOut,
                        otherToken: viewModel.tokenIn,
                        isPresented: isPresented
                    )
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

    @ViewBuilder private func v3RangeView() -> some View {
        VStack(spacing: .margin12) {
            HStack(spacing: .margin12) {
                v3PriceInputView(
                    title: "最低价格",
                    text: $v3LowestPriceInput,
                    isInputActive: $isV3LowestPriceInputActive,
                    onMinus: { viewModel.onTapV3LowestMinus() },
                    onPlus: { viewModel.onTapV3LowestPlus() },
                    onConfirm: {
                        viewModel.onChangeV3LowestPrice(text: v3LowestPriceInput)
                        isV3LowestPriceInputActive = false
                    }
                )

                v3PriceInputView(
                    title: "最高价格",
                    text: $v3HighestPriceInput,
                    isInputActive: $isV3HighestPriceInputActive,
                    onMinus: { viewModel.onTapV3HighestMinus() },
                    onPlus: { viewModel.onTapV3HighestPlus() },
                    onConfirm: {
                        viewModel.onChangeV3HighestPrice(text: v3HighestPriceInput)
                        isV3HighestPriceInputActive = false
                    }
                )
            }

            if let error = viewModel.v3PriceError {
                Text(error)
                    .textCaption(color: .themeLucian)
                    .padding(.horizontal, .margin16)
            }

            v3CurrentPriceView()
            
            HStack(spacing: 0) {
                ForEach([10, 20, 50], id: \.self) { percent in
                    Button(action: {
                        viewModel.setV3TickRange(percent: percent)
                        isV3LowestPriceInputActive = false
                        isV3HighestPriceInputActive = false
                    }) {
                        Text("\(percent)%").textSubhead1(color: .themeLeah)
                    }
                    .frame(maxWidth: .infinity)

                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(Color.themeBlade)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }

                Button(action: {
                    viewModel.setV3TickRange(percent: nil)
                    isV3LowestPriceInputActive = false
                    isV3HighestPriceInputActive = false
                }) {
                    Text("liquidity.tick.full.range".localized).textSubhead1(color: .themeLeah)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, -16)
            .padding(.vertical, .margin16)
            .frame(maxWidth: .infinity)
            .modifier(ThemeListStyleModifier(cornerRadius: 18))
        }
    }

    @ViewBuilder private func v3PriceInputView(title: String, text: Binding<String>, isInputActive: FocusState<Bool>.Binding, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void, onConfirm: @escaping () -> Void) -> some View {
        VStack(spacing: .margin8) {
            Text(title).textSubhead2(color: .themeGray)

            HStack(spacing: .margin12) {
                Button(action: onMinus) {
                    Image("circle_minus_24")
                }

                TextField("", text: text, prompt: Text("0").foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeHeadline2)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused(isInputActive)

                Button(action: onPlus) {
                    Image("circle_plus_24")
                }
            }
        }
        .padding(.vertical, .margin16)
        .frame(maxWidth: .infinity)
        .modifier(ThemeListStyleModifier(cornerRadius: 18))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isInputActive.wrappedValue {
                    HStack {
                        Spacer()
                        Button("确定") {
                            onConfirm()
                        }
                        .foregroundColor(.themeLeah)
                    }
                }
            }
        }
    }

    @ViewBuilder private func v3CurrentPriceView() -> some View {
        VStack(spacing: .margin8) {
            Text("当前价格").textSubhead2(color: .themeGray)
            Text(viewModel.v3CurrentPrice ?? "---")
                .themeHeadline2(color: .themeLeah, alignment: .center)
                .lineLimit(1)
        }
        .padding(.vertical, .margin16)
        .frame(maxWidth: .infinity)
        .modifier(ThemeListStyleModifier(cornerRadius: 18))
    }

    @ViewBuilder private func buttonView() -> some View {
        let approvalButtons = viewModel.approvalButtons

        if !approvalButtons.isEmpty {
            if approvalButtons.count == 1 {
                approvalButton(approvalButtons[0])
            } else {
                HStack(spacing: .margin12) {
                    approvalButton(approvalButtons[0])
                    approvalButton(approvalButtons[1])
                }
            }
        } else {
            let (title, style, disabled, showProgress, preSwapStep) = buttonState()

            ThemeButton(text: title, spinner: showProgress, style: style) {
                viewModel.stopAutoQuoting()

                if let preSwapStep {
                    if let currentQuote = viewModel.currentQuote,
                       let tokenIn = viewModel.tokenIn,
                       let tokenOut = viewModel.tokenOut,
                       let amount = viewModel.amountIn
                    {
                        Coordinator.shared.present { isPresented in
                            currentQuote.provider.preSwapView(
                                step: preSwapStep.0,
                                token0: tokenIn,
                                token1: tokenOut,
                                amount: amount,
                                isPresented: isPresented
                            ) {
                                viewModel.syncQuotes()
                            }

                        } onDismiss: {
                            viewModel.autoQuoteIfRequired()
                        }
                    }
                } else if viewModel.shouldShowTerms {
                    Coordinator.shared.present { isPresented in
                        SwapTermsView(isPresented: isPresented) {
                            viewModel.onAcceptTerms()

                            DispatchQueue.main.async {
                                isInputActive = false
                                sendPresented = true
                            }
                        }
                    }
                } else {
                    isInputActive = false
                    sendPresented = true
                }
            }
            .disabled(disabled)
        }
    }

    @ViewBuilder private func approvalButton(_ item: LiquidityAddViewModel.ApprovalButton) -> some View {
        ThemeButton(text: item.title, spinner: item.state.showProgress, style: item.state.style) {
            viewModel.stopAutoQuoting()

            if let step = item.state.preSwapStep {
                Coordinator.shared.present { isPresented in
                    item.provider.preSwapView(
                        step: step,
                        tokenToApprove: item.token,
                        otherToken: item.otherToken,
                        amount: item.amount,
                        isPresented: isPresented
                    ) {
                        // 审批交易发送成功后，立即刷新并启动区块高度监听刷新模式
                        viewModel.refreshAfterPreSwap()
                        viewModel.startPendingAllowanceRefresh()
                    }
                } onDismiss: {
                    viewModel.refreshAfterPreSwap()
                    viewModel.autoQuoteIfRequired()
                    viewModel.stopPendingAllowanceRefresh()
                }
            }
        }
        .disabled(item.state.disabled)
    }

    @ViewBuilder private func availableBalanceView(valueIn: String?, valueOut: String?) -> some View {
        HStack(spacing: .margin8) {
            Text("send.available_balance".localized).textCaption()
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(valueIn ?? "---")
                    .textCaption()
                    .multilineTextAlignment(.trailing)
                Text(valueOut ?? "---")
                    .textCaption()
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, .margin16)
    }

    @ViewBuilder private func quoteView(quote: LiquidityAddViewModel.Quote) -> some View {
        ListSection {
            HStack(spacing: 4) {
                Button(action: {
                    viewModel.stopAutoQuoting()

                    Coordinator.shared.present { isPresented in
                        LiquidityAddQuotesView(viewModel: viewModel, isPresented: isPresented)
                    } onDismiss: {
                        viewModel.autoQuoteIfRequired()
                    }
                }) {
                    HStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Image(quote.provider.icon)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(4)
                                .frame(width: .iconSize24, height: .iconSize24)

                            Text(quote.provider.name).textSubhead2()
                        }

                        ThemeImage("arrow_s_down", size: 20)
                    }
                }
                .layoutPriority(1)

                Spacer()

                if let price = viewModel.price {
                    HStack {
                        ThemeText(price, style: .captionSB, colorStyle: .primary)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .id(price)
                            .transition(.opacity)
                            .onTapGesture {
                                viewModel.flipPrice()
                            }
                    }
                    .animation(.easeInOut(duration: 0.15), value: price)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
        .themeListStyle(.bordered)
    }

    @ViewBuilder private func quoteCautionsView(quote: LiquidityAddViewModel.Quote) -> some View {
        let cautions = quote.quote.cautions()

        if !cautions.isEmpty {
            ForEach(cautions.indices, id: \.self) { index in
                AlertCardView(caution: cautions[index])
            }
        }
    }

    private func balanceValue() -> String? {
        guard let availableBalance = viewModel.availableBalance, let tokenIn = viewModel.tokenIn else {
            return nil
        }

        return AppValue(token: tokenIn, value: availableBalance).formattedFull()
    }

    private func balanceValueOut() -> String? {
        guard let availableBalance = viewModel.availableBalanceOut, let tokenOut = viewModel.tokenOut else {
            return nil
        }

        return AppValue(token: tokenOut, value: availableBalance).formattedFull()
    }

    private func buttonState() -> (String, ThemeButton.Style, Bool, Bool, (step: MultiSwapPreSwapStep, token: Token, amount: Decimal, provider: ILiquidityAddProvider)?) {
        let title: String
        var style: ThemeButton.Style = .primary
        var disabled = true
        var showProgress = false
        var preSwap: (step: MultiSwapPreSwapStep, token: Token, amount: Decimal, provider: ILiquidityAddProvider)?

        if viewModel.quoting {
            title = "swap.quoting".localized
            showProgress = true
        } else if viewModel.tokenIn == nil {
            title = "swap.select_token_in".localized
        } else if viewModel.tokenOut == nil {
            title = "swap.select_token_out".localized
        } else if viewModel.validProviders.isEmpty {
            title = "swap.no_providers".localized
        } else if viewModel.amountIn == nil {
            title = "swap.enter_amount".localized
        } else if viewModel.isSafeSwapManualAmountOutMode, (viewModel.proceedAmountOut ?? 0) <= 0 {
            title = "swap.enter_amount".localized
        } else if viewModel.amountOutString == nil, !viewModel.isSafeSwapManualAmountOutMode {
            title = "swap.no_providers".localized
        } else if viewModel.adapterState == nil || viewModel.adapterStateOut == nil {
            title = "swap.token_not_enabled".localized
        } else if let adapterState = viewModel.adapterState, adapterState.syncing {
            title = "swap.token_syncing".localized
            showProgress = true
        } else if let adapterStateOut = viewModel.adapterStateOut, adapterStateOut.syncing {
            title = "swap.token_syncing".localized
            showProgress = true
        } else if let adapterState = viewModel.adapterState, !adapterState.isSynced {
            title = "swap.token_not_synced".localized
        } else if let adapterStateOut = viewModel.adapterStateOut, !adapterStateOut.isSynced {
            title = "swap.token_not_synced".localized
        } else if let availableBalance = viewModel.availableBalance, let amountIn = viewModel.amountIn, amountIn > availableBalance {
            title = "swap.insufficient_balance".localized
        } else if let amountOut = viewModel.proceedAmountOut,
                  let availableBalanceOut = viewModel.availableBalanceOut,
                  amountOut > availableBalanceOut
        {
            title = "swap.insufficient_balance".localized
        } else if let currentQuote = viewModel.currentQuote {
            let token: Token
            let amount: Decimal
            let state: MultiSwapButtonState
            
            if let state0 = currentQuote.quote.customButtonState0, let tokenIn = viewModel.tokenIn, let amountIn = viewModel.amountIn {
                state = state0
                token = tokenIn
                amount = amountIn
            } else if let state1 = currentQuote.quote.customButtonState1, let tokenOut = viewModel.tokenOut, let amountOut = viewModel.currentQuote?.quote.expectedBuyAmount {
                state = state1
                token = tokenOut
                amount = amountOut
            } else {
                title = "swap.proceed_button".localized
                disabled = false
                return (title, style, disabled, showProgress, preSwap)
            }
            
            title = state.title
            style = state.style
            disabled = state.disabled
            showProgress = state.showProgress

            if let step = state.preSwapStep {
                preSwap = (step, token, amount, currentQuote.provider)
            }
        } else if viewModel.isSafeSwapManualAmountOutMode {
            title = "swap.proceed_button".localized
            disabled = false
        } else {
            title = "swap.proceed_button".localized
            disabled = false
        }

        return (title, style, disabled, showProgress, preSwap)
    }

    func presentTokenIn() {
        Coordinator.shared.present { isPresented in
            MultiSwapTokenSelectView(
                title: "swap.you_pay".localized,
                currentToken: $viewModel.tokenIn,
                otherToken: viewModel.tokenOut,
                isPresented: isPresented
            )
        }
    }
}
