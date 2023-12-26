import Foundation
import RxSwift
import RxCocoa
import MarketKit
import ComponentKit

class TransactionsViewModel: BaseTransactionsViewModel {
    private let service: TransactionsService
    private let disposeBag = DisposeBag()

    private let blockchainTitleRelay = BehaviorRelay<String?>(value: nil)
    private let tokenTitleRelay = BehaviorRelay<String?>(value: nil)

    init(service: TransactionsService, contactLabelService: TransactionsContactLabelService, factory: TransactionsViewItemFactory) {
        self.service = service

        super.init(service: service, contactLabelService: contactLabelService, factory: factory)

        subscribe(disposeBag, service.blockchainObservable) { [weak self] in self?.syncBlockchainTitle(blockchain: $0) }
        subscribe(disposeBag, service.tokenObservable) { [weak self] in self?.syncTokenTitle(token: $0) }

        syncBlockchainTitle(blockchain: service.blockchain)
        syncTokenTitle(token: service.token)
    }

    private func syncBlockchainTitle(blockchain: SelectedBlockchain?) {
        let title: String

        if let blockchain = blockchain {
            switch blockchain {
            case .blockchain(let chain):
                title = chain.name
            case .blockchainSeries(let series):
                title = series.title
            }
        } else {
            title = "transactions.all_blockchains".localized
        }


        blockchainTitleRelay.accept(title)
    }

    private func syncTokenTitle(token: Token?) {
        var title: String

        if let token {
            title = token.coin.code

            if let badge = token.badge {
                title += " (\(badge))"
            }
        } else {
            title = "transactions.all_coins".localized
        }

        tokenTitleRelay.accept(title)
    }

}

extension TransactionsViewModel {

    var blockchainTitleDriver: Driver<String?> {
        blockchainTitleRelay.asDriver()
    }

    var tokenTitleDriver: Driver<String?> {
        tokenTitleRelay.asDriver()
    }

    var blockchainViewItems: [BlockchainViewItem] {
        var allBlockchains = service.allBlockchains.sorted { $0.type.order < $1.type.order }
        
        let item0 = [BlockchainViewItem(selectedType: nil, title: "transactions.all_blockchains".localized, selected: service.blockchain == nil)]
        
        let bitcoinSeries = buildSeriesBlockchainViewItem(chain: .Bitcoin, allBlockchains: &allBlockchains)
        
        let otherItems = allBlockchains.map { blockchain in
                    BlockchainViewItem(selectedType: .blockchain(blockchain: blockchain), title: blockchain.name, selected: service.blockchain == .blockchain(blockchain: blockchain))
                }
        
        return item0 + bitcoinSeries + otherItems
    }
    
    func buildSeriesBlockchainViewItem(chain: BlockchainSeries, allBlockchains: inout [Blockchain]) -> [BlockchainViewItem] {
        if chain.isContains(allBlockchains.map{$0.type}) {
            chain.complement(blockchains: &allBlockchains)
            return [BlockchainViewItem(selectedType: .blockchainSeries(series: chain), title: chain.title, selected: service.blockchain ==  .blockchainSeries(series: chain))]
        }
        return []
    }
    var token: Token? {
        service.token
    }

    func onSelectBlockchain(type: SelectedBlockchain?) {
        service.set(blockchain: type)
    }

    func onSelect(token: Token?) {
        service.set(token: token)
    }

}


