import Combine
import Foundation
import MarketKit

class ReceiveBlockchainListViewModel: ObservableObject {
    private let fullCoin: FullCoin
    private let account: Account

    init(fullCoin: FullCoin, account: Account) {
        self.fullCoin = fullCoin
        self.account = account
    }
}

extension ReceiveBlockchainListViewModel {
    var viewItems: [ReceiveBlockchainListViewModel.ViewItem] {
        let tokens = fullCoin.tokens
            .filter { account.type.supports(token: $0) && ChildWalletBridge.shared.supports(account: account, token: $0) }
            .sorted(by: SortCriterion.blockchainList, context: TokenSortContext())

        return tokens.map {
            .init(
                uid: $0.blockchain.uid,
                imageUrl: $0.blockchainType.imageUrl,
                title: $0.blockchain.name,
                subtitle: $0.blockchainType.description
            )
        }
    }

    func item(uid: String) -> Token? {
        fullCoin.tokens.first { $0.blockchain.uid == uid }
    }
}

extension ReceiveBlockchainListViewModel {
    struct ViewItem: Hashable, Identifiable {
        let uid: String
        let imageUrl: String?
        let title: String
        let subtitle: String

        var id: String { uid }
    }
}
