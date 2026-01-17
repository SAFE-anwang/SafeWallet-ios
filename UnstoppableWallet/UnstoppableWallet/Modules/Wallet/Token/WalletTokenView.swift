import SwiftUI

struct WalletTokenView: View {
    private let wallet: Wallet
    private var lockedAmount: Decimal?
    init(wallet: Wallet) {
        self.wallet = wallet
        let adapter = Core.shared.adapterManager.adapter(for: wallet)
        if let _adapter  = adapter as? EvmAdapter {
            lockedAmount = _adapter.balanceData.locked
        }else if let _adapter = adapter as? Eip20Adapter {
            lockedAmount = _adapter.balanceData.locked
        }
    }

    var body: some View {
        BaseWalletTokenView(wallet: wallet) { walletTokenViewModel, transactionsViewModel in
            ViewWithTransactionList(
                transactionListStatus: transactionsViewModel.transactionListStatus,
                content: {
                    Group {
                        WalletTokenTopView(viewModel: walletTokenViewModel).themeListTopView()
                        locekdView()
                    }
                },
                transactionList: {
                    TransactionsView(viewModel: transactionsViewModel, statPage: .tokenPage)
                }
            )
        }
    }
    @ViewBuilder private func locekdView() -> some View {
        if let lockedAmount, lockedAmount > 0 {
            WalletInfoView.infoView(
                title: "balance.token.locked".localized,
                info: .init(
                    title: "balance.token.locked.info.title".localized,
                    description: "balance.token.locked.info.description".localized
                ),
                value: infoAmount(value: lockedAmount)
            )
            .overlay(RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
            .stroke(Color.themeGray50, lineWidth: .heightOneDp))
        }
    }
    
    private func infoAmount(value: Decimal) -> WalletInfoView.ValueFormatStyle {
        .fullAmount(.init(kind: .token(token: wallet.token), value: value))
    }
}
