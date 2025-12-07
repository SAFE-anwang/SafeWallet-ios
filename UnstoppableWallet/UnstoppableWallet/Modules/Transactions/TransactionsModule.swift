import MarketKit

struct TransactionItem: Comparable {
    var record: TransactionRecord
    var status: TransactionStatus
    var lockState: TransactionLockState?

    static func < (lhs: TransactionItem, rhs: TransactionItem) -> Bool {
        lhs.record < rhs.record
    }

    static func == (lhs: TransactionItem, rhs: TransactionItem) -> Bool {
        lhs.record == rhs.record
    }
}

struct TransactionFilter: Equatable {
    private(set) var blockchain: FilterBlockchainType?
    private(set) var blockchainUIds: [String]?
    private(set) var token: Token?
    private(set) var contact: Contact?
    var scamFilterEnabled: Bool
    
    var safe4IncomeEnabled: Bool
    var safe4NodestatusEnabled: Bool
    
    init() {
        blockchain = nil
        token = nil
        contact = nil
        scamFilterEnabled = true
        safe4IncomeEnabled = UserDefaultsStorage().value(for: safe4key_IncomeEnabled) ?? true
        safe4NodestatusEnabled = UserDefaultsStorage().value(for: safe4key_Nodestatus) ?? true
    }
    
    init(token: Token) {
        blockchain = .blockchain(blockchain: token.blockchain)
        self.token = token
        contact = nil
        scamFilterEnabled = true
        safe4IncomeEnabled = UserDefaultsStorage().value(for: safe4key_IncomeEnabled) ?? true
        safe4NodestatusEnabled = UserDefaultsStorage().value(for: safe4key_Nodestatus) ?? true
    }

    var hasChanges: Bool {
        blockchain != nil || token != nil || contact != nil || !scamFilterEnabled || !safe4IncomeEnabled || !safe4NodestatusEnabled
    }

    private mutating func updateContact() {
        guard let blockchain, let contact else {
            return
        }

        // reset contact if selected blockchain not allowed for search by contact
        guard let uids = blockchainUIds, Set(uids).isSubset(of: Set(TransactionContactSelectViewModel.allowedBlockchainUids)) else {
            self.contact = nil
            return
        }

        guard contact.hasOne(of: uids) else {
            self.contact = nil
            return
        }

    }

    mutating func set(blockchain: FilterBlockchainType?, blockchainUIds: [String]?) {
        self.blockchain = blockchain
        self.blockchainUIds = blockchainUIds
        token = nil

        updateContact()
    }

    mutating func set(token: Token?) {
        self.token = token
        if let _blockchain = token?.blockchain {
            blockchain = .blockchain(blockchain: _blockchain)
        }else {
            blockchain = nil
        }
        

        updateContact()
    }

    mutating func set(contact: Contact?) {
        self.contact = contact
    }

    mutating func reset() {
        blockchain = nil
        token = nil
        contact = nil
        scamFilterEnabled = true
        safe4IncomeEnabled = true
        safe4NodestatusEnabled = true
    }
}

extension TransactionFilter {
    
    enum FilterBlockchainType: Equatable {
        case blockchain(blockchain: Blockchain)
        case blockchainSeries(series: BlockchainSeries)
        
        var name: String {
            switch self {
            case let .blockchain(blockchain):
                return blockchain.name
            case let .blockchainSeries(series):
                return series.title
            }
        }
                
        public static func == (lhs: FilterBlockchainType, rhs: FilterBlockchainType) -> Bool {
            switch (lhs, rhs) {
            case let (.blockchain(lBlockchain), .blockchain(rBlockchain)): return lBlockchain == rBlockchain
            case let (.blockchainSeries(lSeries), .blockchainSeries(rSeries)): return lSeries == rSeries
            default: return false
            }
        }
    }
    
    enum BlockchainSeries: String, CaseIterable, Identifiable, Codable {
        
        case BitcoinSeries

        var supportedTypes: [BlockchainType] {
            switch self {
            case .BitcoinSeries: return [.bitcoin, .litecoin, .dash, .bitcoinCash]
            }
        }
        
        var title: String {
            switch self {
            case .BitcoinSeries: return "transactions.series".localized("Bitcoin")
            }
        }
        
        var id: Self {
            self
        }
        
        func hasOne(of blockchainTypes: [BlockchainType]) -> Bool {
            !Set(blockchainTypes).intersection(Set(supportedTypes)).isEmpty
        }
        
        func uids(blockchains: [Blockchain]) -> [String] {
            blockchains.filter{supportedTypes.contains($0.type)}.map{$0.uid}
        }

        func complement(blockchains: inout [Blockchain]) {
            blockchains = blockchains.filter {  blockchain in
                !supportedTypes.contains(where: { $0 == blockchain.type })
            }
        }
    }
}
