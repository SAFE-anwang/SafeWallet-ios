import Combine
import MarketKit

let safe4key_IncomeEnabled = "coin-safe4-IncomeEnabled-key"
let safe4key_Nodestatus = "coin-safe4-Nodestatus-key"

class TransactionFilterViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    @Published var transactionsViewModel: TransactionsViewModel
    @Published var blockchain: TransactionFilter.FilterBlockchainType?
    @Published var token: Token?
    @Published var contact: Contact?
    
    @Published var scamFilterEnabled: Bool
    @Published var resetEnabled: Bool
    @Published var safe4IncomeEnabled: Bool
    @Published var safe4NodestatusEnabled: Bool

    init(transactionsViewModel: TransactionsViewModel) {
        self.transactionsViewModel = transactionsViewModel

        blockchain = transactionsViewModel.transactionFilter.blockchain
        token = transactionsViewModel.transactionFilter.token
        contact = transactionsViewModel.transactionFilter.contact
        scamFilterEnabled = transactionsViewModel.transactionFilter.scamFilterEnabled
        resetEnabled = transactionsViewModel.transactionFilter.hasChanges
        safe4IncomeEnabled = transactionsViewModel.transactionFilter.safe4IncomeEnabled
        safe4NodestatusEnabled = transactionsViewModel.transactionFilter.safe4NodestatusEnabled

        transactionsViewModel.$transactionFilter
            .sink { [weak self] filter in
                self?.blockchain = filter.blockchain
                self?.token = filter.token
                self?.contact = filter.contact
                self?.scamFilterEnabled = filter.scamFilterEnabled
                self?.resetEnabled = filter.hasChanges
                self?.safe4IncomeEnabled = filter.safe4IncomeEnabled
                self?.safe4NodestatusEnabled = filter.safe4NodestatusEnabled
            }
            .store(in: &cancellables)
    }
    
    func set(blockchain: TransactionFilter.FilterBlockchainType?, blockchainUIds: [String]?) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.set(blockchain: blockchain, blockchainUIds: blockchainUIds)
        transactionsViewModel.transactionFilter = newFilter
    }
    
    var uids: [String]? {
        transactionsViewModel.transactionFilter.blockchainUIds
    }

    func set(token: Token?) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.set(token: token)
        transactionsViewModel.transactionFilter = newFilter
    }

    func set(contact: Contact?) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.set(contact: contact)
        transactionsViewModel.transactionFilter = newFilter
    }

    func set(scamFilterEnabled: Bool) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.scamFilterEnabled = scamFilterEnabled
        transactionsViewModel.transactionFilter = newFilter
    }
    
    func set(safe4IncomeEnabled: Bool) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.safe4IncomeEnabled = safe4IncomeEnabled
        transactionsViewModel.transactionFilter = newFilter
        UserDefaultsStorage().set(value: safe4IncomeEnabled, for: safe4key_IncomeEnabled)
    }
    
    func set(safe4NodestatusEnabled: Bool) {
        var newFilter = transactionsViewModel.transactionFilter
        newFilter.safe4NodestatusEnabled = safe4NodestatusEnabled
        transactionsViewModel.transactionFilter = newFilter
        UserDefaultsStorage().set(value: safe4NodestatusEnabled, for: safe4key_Nodestatus)
    }

    func reset() {
        transactionsViewModel.transactionFilter.reset()
    }
}
