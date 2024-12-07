import Combine
import MarketKit

class TransactionFilterViewModel: ObservableObject {
    private let service: TransactionsService
    private var cancellables = Set<AnyCancellable>()
    @Published var blockchain: TransactionFilter.FilterBlockchainType?
    @Published var token: Token?
    @Published var contact: Contact?
    
    @Published var scamFilterEnabled: Bool
    @Published var resetEnabled: Bool
    
    @Published var safe4IncomeEnabled: Bool
    @Published var safe4NodestatusEnabled: Bool

    init(service: TransactionsService) {
        self.service = service
        
        blockchain = service.transactionFilter.blockchain
        token = service.transactionFilter.token
        contact = service.transactionFilter.contact
        scamFilterEnabled = service.transactionFilter.scamFilterEnabled
        resetEnabled = service.transactionFilter.hasChanges
        safe4IncomeEnabled = service.transactionFilter.safe4IncomeEnabled
        safe4NodestatusEnabled = service.transactionFilter.safe4NodestatusEnabled
        
        service.$transactionFilter
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
        var newFilter = service.transactionFilter
        newFilter.set(blockchain: blockchain, blockchainUIds: blockchainUIds)
        service.transactionFilter = newFilter
    }
    
    var uids: [String]? {
        service.transactionFilter.blockchainUIds
    }

    func set(token: Token?) {
        var newFilter = service.transactionFilter
        newFilter.set(token: token)
        service.transactionFilter = newFilter
    }

    func set(contact: Contact?) {
        var newFilter = service.transactionFilter
        newFilter.set(contact: contact)
        service.transactionFilter = newFilter
    }

    func set(scamFilterEnabled: Bool) {
        var newFilter = service.transactionFilter
        newFilter.scamFilterEnabled = scamFilterEnabled
        service.transactionFilter = newFilter
    }
    
    func set(safe4IncomeEnabled: Bool) {
        var newFilter = service.transactionFilter
        newFilter.safe4IncomeEnabled = safe4IncomeEnabled
        UserDefaultsStorage().set(value: safe4IncomeEnabled, for: safe4key_IncomeEnabled)
        service.transactionFilter = newFilter
    }
    
    func set(safe4NodestatusEnabled: Bool) {
        var newFilter = service.transactionFilter
        newFilter.safe4NodestatusEnabled = safe4NodestatusEnabled
        UserDefaultsStorage().set(value: safe4NodestatusEnabled, for: safe4key_Nodestatus)
        service.transactionFilter = newFilter
    }

    func reset() {
        var newFilter = service.transactionFilter
        newFilter.reset()
        service.transactionFilter = newFilter
    }
}
