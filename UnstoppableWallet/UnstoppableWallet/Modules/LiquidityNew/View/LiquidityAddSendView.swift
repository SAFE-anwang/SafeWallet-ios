import MarketKit
import SwiftUI

struct LiquidityAddSendView: View {
    @StateObject var sendViewModel: SendViewModel
    private let onFinish: () -> Void
    
    init(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider, v3TickType: LiquidityTickType? = nil, manualAmountOutMode: Bool = false, onFinish: @escaping () -> Void) {
        _sendViewModel = .init(wrappedValue: SendViewModel(sendData: .liquidityAdd(token0: token0, token1: token1, amount0: amount0, amount1: amount1, provider: provider, v3TickType: v3TickType, manualAmountOutMode: manualAmountOutMode)))
        self.onFinish = onFinish
    }

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                SendView(viewModel: sendViewModel)
            } bottomContent: {
                switch sendViewModel.state {
                case .syncing:
                    if sendViewModel.sendData != nil {
                        ThemeButton(text: "swap.quoting".localized, spinner: true, style: .secondary) {}
                            .disabled(true)
                    }
                case .success:
                    if sendViewModel.canSend {
                        SlideButton(
                            styling: .text(start: "swap.confirmation.slide_to_swap".localized, end: "", success: ""),
                            action: {
                                try await sendViewModel.send()
                            }, completion: {
                                HudHelper.instance.show(banner: .liquidity)
                                onFinish()
                            }
                        )
                    } else {
                        ThemeButton(text: "send.confirmation.refresh".localized, style: .secondary) {
                            sendViewModel.sync()
                        }
                    }
                case .failed:
                    ThemeButton(text: "send.confirmation.refresh".localized, style: .secondary) {
                        sendViewModel.sync()
                    }
                }
            }
        }
        .navigationTitle("send.confirmation.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
