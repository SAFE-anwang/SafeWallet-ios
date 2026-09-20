import MarketKit
import SwiftUI
import BigInt

enum LiquidityRemoveDisplayData {
    case v2(token0: Token, token1: Token, amount0: String, amount1: String, liquidity: String)
    case v3(token0: Token, token1: Token, amount0: BigUInt, amount1: BigUInt, lpName: String, tokenId: String, state: String, isInRange: Bool)
}

struct LiquidityRemoveSendView: View {
    @Binding private var isPresented: Bool
    private let makeSendData: (BigUInt) -> SendData
    private let onSuccess: () -> Void
    private let allowsContinuousRatio: Bool
    private let displayData: LiquidityRemoveDisplayData
    @State private var ratio: BigUInt
    @State private var ratioValue: Double

    init(isPresented: Binding<Bool>, allowsContinuousRatio: Bool = false, displayData: LiquidityRemoveDisplayData, makeSendData: @escaping (BigUInt) -> SendData, onSuccess: @escaping () -> Void = {}) {
        _isPresented = isPresented
        self.allowsContinuousRatio = allowsContinuousRatio
        self.displayData = displayData
        self.makeSendData = makeSendData
        self.onSuccess = onSuccess
        let initialRatio: Double = allowsContinuousRatio ? 0 : 100
        _ratio = State(initialValue: BigUInt(Int(initialRatio)))
        _ratioValue = State(initialValue: initialRatio)
    }

    var body: some View {
        ThemeView {
            LiquidityRemoveSendContent(
                sendData: makeSendData(ratio),
                displayData: displayData,
                selectedRatio: $ratio,
                ratioValue: $ratioValue,
                allowsContinuousRatio: allowsContinuousRatio,
                isPresented: $isPresented,
                onSuccess: onSuccess
            )
            .id(ratio)
        }
        .navigationTitle("liquidity.remove".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LiquidityRemoveLegacySummary: View {
    let data: LiquidityRemoveDisplayData
    let selectedRatio: BigUInt
    @Binding var ratioValue: Double
    let onRatioChanged: (BigUInt) -> Void

    var body: some View {
        switch data {
        case let .v2(token0, token1, amount0, amount1, liquidity):
            LiquidityRemoveCard {
                LiquidityRemoveTokenRow(token: token0, title: token0.coin.code, amount: amount0)
                Divider().padding(.horizontal, .margin12)
                LiquidityRemoveTokenRow(token: token1, title: token1.coin.code, amount: amount1)
                Divider().padding(.horizontal, .margin12)
                HStack {
                    Text(liquidity).textHeadline2(color: .themeLeah)
                    Spacer()
                }
                .padding(.horizontal, .margin12)
                .frame(height: 62)
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin4)
        case let .v3(token0, token1, amount0, amount1, lpName, tokenId, state, isInRange):
            LiquidityRemoveV3Summary(
                token0: token0,
                token1: token1,
                amount0: amount0,
                amount1: amount1,
                lpName: lpName,
                tokenId: tokenId,
                state: state,
                isInRange: isInRange,
                selectedRatio: selectedRatio,
                ratioValue: $ratioValue,
                onRatioChanged: onRatioChanged
            )
        }
    }
}

private struct LiquidityRemoveV3Summary: View {
    let token0: Token
    let token1: Token
    let amount0: BigUInt
    let amount1: BigUInt
    let lpName: String
    let tokenId: String
    let state: String
    let isInRange: Bool
    let selectedRatio: BigUInt
    @Binding var ratioValue: Double
    let onRatioChanged: (BigUInt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: .margin8) {
                CoinIconView(token: token1)
                CoinIconView(token: token0)
                Text(lpName).textHeadline2(color: .themeLeah)
                Spacer()
                BadgeViewNew(state, colorStyle: isInRange ? .green : .red)
            }
            .padding(.horizontal, .margin16)
            .padding(.top, .margin16)

            Text(tokenId).textSubhead2(color: .themeGray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .margin16)
                .padding(.top, .margin8)

            Text("liquidity.remove.rate.title".localized).textCaption()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .margin16)
                .padding(.top, .margin24)

            LiquidityRemoveV3RatioSelector(ratioValue: $ratioValue, selectedRatio: selectedRatio, onRatioChanged: onRatioChanged)
                .padding(.horizontal, .margin16)
                .padding(.top, .margin8)

            Text("liquidity.remove.receive.title".localized).textSubhead2()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .margin16)
                .padding(.top, 25)
                .padding(.bottom, .margin16)

            LiquidityRemoveCard {
                LiquidityRemoveTokenRow(token: token0, title: "liquidity.remove.pooled".localized + token0.coin.code, amount: formatted(amount0, token: token0), compact: true)
                Divider().padding(.horizontal, .margin12)
                LiquidityRemoveTokenRow(token: token1, title: "liquidity.remove.pooled".localized + token1.coin.code, amount: formatted(amount1, token: token1), compact: true)
            }
            .padding(.horizontal, .margin16)
        }
        .padding(.vertical, .margin4)
    }

    private func formatted(_ value: BigUInt, token: Token) -> String {
        let scaledValue = value * selectedRatio / 100
        let decimal = Decimal(bigUInt: scaledValue, decimals: token.decimals) ?? 0
        return Self.ratioFormatter.string(from: decimal as NSNumber) ?? ""
    }

    private static let ratioFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter
    }()
}

private struct LiquidityRemoveV3RatioSelector: View {
    @Binding var ratioValue: Double
    let selectedRatio: BigUInt
    let onRatioChanged: (BigUInt) -> Void

    var body: some View {
        VStack(spacing: .margin16) {
            HStack {
                Text("\(Int(ratioValue))%").textTitle3(color: .themeLeah)
                Spacer()
            }

            Slider(value: $ratioValue, in: 0 ... 100, step: 1) { editing in
                if !editing {
                    onRatioChanged(BigUInt(Int(ratioValue)))
                }
            }
            .tint(.themeRemus)

            HStack(spacing: .margin8) {
                ForEach([25, 50, 75, 100], id: \.self) { value in
                    ThemeButton(text: "\(value)%", style: selectedRatio == BigUInt(value) ? .primary : .secondary, size: .small) {
                        ratioValue = Double(value)
                        onRatioChanged(BigUInt(value))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.margin16)
        .frame(height: 150)
        .background(Color.themeLawrence)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: .cornerRadius16, style: .continuous).stroke(Color(hex: 0x73798C), lineWidth: 1))
    }
}

private struct LiquidityRemoveCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.themeLawrence)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius16, style: .continuous))
    }
}

private struct LiquidityRemoveTokenRow: View {
    let token: Token
    let title: String
    let amount: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? .margin16 : .margin16) {
            CoinIconView(token: token, size: compact ? .iconSize24 : .iconSize32)
            if compact {
                Text(title).textBody(color: .themeLeah)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).textHeadline2(color: .themeLeah)
                    Text(token.protocolName ?? token.type.description).textCaptionSB(color: .themeGray)
                }
            }
            Spacer()
            if compact {
                Text(amount).textCaption(color: .themeLeah)
            } else {
                Text(amount).textHeadline2(color: .themeLeah)
            }
        }
        .padding(.horizontal, compact ? .margin16 : .margin16)
        .frame(height: compact ? 56 : 62)
    }
}

private struct LiquidityRemoveSendContent: View {
    @StateObject private var viewModel: SendViewModel
    private let displayData: LiquidityRemoveDisplayData
    @Binding private var selectedRatio: BigUInt
    @Binding private var ratioValue: Double
    private let allowsContinuousRatio: Bool
    @Binding private var isPresented: Bool
    private let onSuccess: () -> Void
    @State private var showConfirmation = false
    @State private var confirmed = false

    init(sendData: SendData, displayData: LiquidityRemoveDisplayData, selectedRatio: Binding<BigUInt>, ratioValue: Binding<Double>, allowsContinuousRatio: Bool, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) {
        _viewModel = .init(wrappedValue: SendViewModel(sendData: sendData))
        self.displayData = displayData
        _selectedRatio = selectedRatio
        _ratioValue = ratioValue
        self.allowsContinuousRatio = allowsContinuousRatio
        _isPresented = isPresented
        self.onSuccess = onSuccess
    }

    var body: some View {
        BottomGradientWrapper {
            VStack(spacing: .margin16) {
                LiquidityRemoveLegacySummary(data: displayData, selectedRatio: selectedRatio, ratioValue: $ratioValue) { value in
                    selectedRatio = value
                }
                if !allowsContinuousRatio {
                    fixedRatioSelector
                }
                SendView(viewModel: viewModel)
            }
        } bottomContent: {
            if viewModel.state.isSuccess && viewModel.canSend && !viewModel.expired && !viewModel.partiallyExecuted {
                SlideButton(
                    styling: .text(start: "liquidity.remove".localized, end: "", success: ""),
                    action: {
                        guard confirmed else {
                            showConfirmation = true
                            throw ConfirmationRequiredError()
                        }
                        try await viewModel.send()
                    },
                    completion: {
                        complete()
                    }
                )
            } else if viewModel.partiallyExecuted {
                Text("transactions.pending".localized).textSubhead2(color: .themeGray)
            } else if viewModel.state.isSyncing {
                ThemeButton(text: "swap.quoting".localized, spinner: true, style: .secondary) {}
                    .disabled(true)
            } else if viewModel.state.isSuccess && viewModel.sendData?.canSend == false {
                ThemeButton(text: "liquidity.remove".localized, style: .secondary) {}
                    .disabled(true)
            } else {
                ThemeButton(text: "send.confirmation.refresh".localized, style: .secondary) {
                    viewModel.sync()
                }
            }
        }
        .alert("liquidity.remove".localized, isPresented: $showConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("button.confirm".localized) {
                confirmed = true
                Task {
                    do {
                        try await viewModel.send()
                        complete()
                    } catch {
                        // SendViewModel publishes the actionable error to SendView.
                    }
                }
            }
        } message: {
            Text("liquidity.remove.description".localized)
        }
    }

    private var fixedRatioSelector: some View {
        HStack(spacing: .margin8) {
            ForEach([25, 50, 75, 100], id: \.self) { value in
                ThemeButton(text: "\(value)%", style: selectedRatio == BigUInt(value) ? .primary : .secondary, size: .small) {
                    selectedRatio = BigUInt(value)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, .margin16)
        .frame(height: 44)
        .background(Color.themeNavigationBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.themeBlade)
                .frame(height: .heightOneDp)
        }
    }

    private func complete() {
        HudHelper.instance.show(banner: .success(string: "liquidity.remove.succ".localized))
        isPresented = false
        onSuccess()
    }

    private struct ConfirmationRequiredError: Error {}
}
