import Combine
import MarketKit

class TransactionBlockchainSelectViewModel: ObservableObject {
    private let transactionFilterViewModel: TransactionFilterViewModel
    private let walletManager = App.shared.walletManager

    let blockchains: [Blockchain]
    let allBlockchainSeries: [TransactionFilter.BlockchainSeries]

    init(transactionFilterViewModel: TransactionFilterViewModel) {
        self.transactionFilterViewModel = transactionFilterViewModel
        let blockchains = Array(Set(walletManager.activeWallets.map(\.token.blockchain)))
        self.blockchains = blockchains
        allBlockchainSeries = TransactionFilter.BlockchainSeries.allCases
            .filter{ $0.hasOne(of: blockchains.map(\.type))}
    }

    var currentBlockchain: TransactionFilter.FilterBlockchainType? {
        transactionFilterViewModel.blockchain
    }
    
    func set(currentBlockchain: TransactionFilter.FilterBlockchainType?, blockchainUIds: [String]?) {
        transactionFilterViewModel.set(blockchain: currentBlockchain, blockchainUIds: blockchainUIds)
    }
}
