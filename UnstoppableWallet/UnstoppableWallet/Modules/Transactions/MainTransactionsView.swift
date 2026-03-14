import SwiftUI

struct MainTransactionsView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel

    var body: some View {
        ThemeView {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: TransactionTypeFilter.allCases.map(\.title),
                    currentTabIndex: Binding(
                        get: {
                            TransactionTypeFilter.allCases.firstIndex(of: transactionsViewModel.typeFilter) ?? 0
                        },
                        set: { index in
                            transactionsViewModel.typeFilter = TransactionTypeFilter.allCases[index]
                        }
                    )
                )

                if transactionsViewModel.sections.isEmpty {
                    PlaceholderViewNew(icon: "warning_filled", subtitle: "transactions.empty_text".localized)
                } else {
                    ThemeList(bottomSpacing: .margin16) {
                        TransactionsView(viewModel: transactionsViewModel, statPage: .transactions)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("transactions.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar() }
        }
    }
    
    @ToolbarContentBuilder func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if transactionsViewModel.syncing {
                ProgressView()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                Coordinator.shared.present { isPresented in
                    TransactionFilterView(transactionsViewModel: transactionsViewModel, isPresented: isPresented)
                }
                stat(page: .transactions, event: .open(page: .transactionFilter))
            }) {
                ZStack {
                    Image("manage_2_24").themeIcon(color: .themeGray)

                    if transactionsViewModel.transactionFilter.hasChanges {
                        VStack {
                            HStack {
                                Spacer()
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: 28, height: 28)
            }
        }
    }
}
