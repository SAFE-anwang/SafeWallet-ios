import Combine
import EvmKit
import Foundation
import MarketKit

class AddTokenViewModel: ObservableObject {
    private let account: Account
    private let items: [AddTokenModule.Item]
    private let coinManager: CoinManager
    private let walletManager: WalletManager

    private var fetchTask: Task<Void, Never>?

    @Published private(set) var state: State = .idle
    @Published private(set) var currentBlockchainItem: CurrentBlockchainItem
    @Published var reference: String = ""

    private var cancellables = Set<AnyCancellable>()

    private let finishSubject = PassthroughSubject<Void, Never>()
    var finishPublisher: AnyPublisher<Void, Never> {
        finishSubject.eraseToAnyPublisher()
    }

    init(account: Account, items: [AddTokenModule.Item], coinManager: CoinManager, walletManager: WalletManager) {
        let sortedItems = items.sorted(by: { $0.blockchain.type.order < $1.blockchain.type.order })

        self.account = account
        self.items = sortedItems
        self.coinManager = coinManager
        self.walletManager = walletManager

        currentBlockchainItem = CurrentBlockchainItem(item: sortedItems[0])

        $reference
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncState()
            }
            .store(in: &cancellables)
    }

    private func syncState() {
        fetchTask?.cancel()
        fetchTask = nil

        let trimmed = reference.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            state = .idle
            return
        }

        let service = items.by(currentBlockchainItem.blockchain).service

        do {
            try service.validate(reference: trimmed)
        } catch {
            state = .failed(error: error)
            return
        }

        let tokenQuery = service.tokenQuery(reference: trimmed)

        if let existingToken = try? coinManager.token(query: tokenQuery) {
            let childWalletId = ChildWalletBridge.shared.activeChildWalletId(account: account)
            let isEnabled = walletManager.wallets(account: account, childWalletId: childWalletId).contains {
                $0.token.tokenQuery.id.caseInsensitiveCompare(tokenQuery.id) == .orderedSame
            }

            if isEnabled || !canAddUnpromotedSafe4Token(tokenQuery: tokenQuery) {
                state = .alreadyExists(token: existingToken)
            } else {
                state = .fetched(token: existingToken)
            }
            return
        }

        state = .loading

        fetchTask = Task { [weak self, service, trimmed] in
            do {
                let token = try await service.token(reference: trimmed)
                await MainActor.run { [weak self] in self?.state = .fetched(token: token) }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in self?.state = .failed(error: error) }
                }
            }
        }
    }

    private func canAddUnpromotedSafe4Token(tokenQuery: TokenQuery) -> Bool {
        guard tokenQuery.blockchainType == .safe4,
              case let .eip20(address) = tokenQuery.tokenType,
              let record = try? Core.shared.safe4CustomTokenStorage.asset(address: address, chainId: Safe4Network.currentChainId),
              let ownerAddress = safe4OwnerAddress(account: account)
        else {
            return false
        }

        return Safe4TokenAddPolicy.canAddUnpromotedToken(
            isPromoted: record.isPromoted,
            creator: record.creator,
            ownerAddress: ownerAddress
        )
    }

    private func safe4OwnerAddress(account: Account) -> String? {
        guard let chain = Core.shared.evmBlockchainManager.chain(chainId: Safe4Network.currentChainId) else {
            return nil
        }

        let bridge = ChildWalletBridge.shared
        let identity = bridge.identity(account: account)
        if identity.childWallet != nil {
            do {
                guard let address = try bridge.evmAddress(identity: identity, chain: chain) else {
                    return nil
                }
                return address.eip55
            } catch {
                return nil
            }
        }

        return try? AccountAddress.evmAddress(account: account, blockchainType: .safe4).eip55
    }
}

enum Safe4TokenAddPolicy {
    static func canAddUnpromotedToken(isPromoted: Bool, creator: String, ownerAddress: String?) -> Bool {
        guard !isPromoted, let ownerAddress else {
            return false
        }

        return creator.caseInsensitiveCompare(ownerAddress) != .orderedSame
    }
}

extension AddTokenViewModel {
    var canAddToken: Bool {
        account.type.canAddTokens
    }

    var blockchains: [Blockchain] {
        items.map(\.blockchain)
    }

    var placeholder: String {
        currentBlockchainItem.placeholder
    }

    var loading: Bool {
        if case .loading = state { return true }
        return false
    }

    var buttonEnabled: Bool {
        if case .fetched = state { return true }
        return false
    }

    var cautionState: CautionState {
        switch state {
        case .alreadyExists:
            return .caution(Caution(text: "add_token.already_added".localized, type: .warning))
        case let .failed(error):
            return .caution(Caution(text: error.convertedError.localizedDescription, type: .error))
        default:
            return .none
        }
    }

    var viewItem: ViewItem? {
        switch state {
        case let .alreadyExists(token):
            return ViewItem(name: token.coin.name, code: token.coin.code, decimals: String(token.decimals))
        case let .fetched(token):
            return ViewItem(name: token.coin.name, code: token.coin.code, decimals: String(token.decimals))
        default:
            return nil
        }
    }

    func set(blockchain: Blockchain) {
        currentBlockchainItem = CurrentBlockchainItem(item: items.by(blockchain))
        syncState()
    }

    func save() {
        guard case let .fetched(token) = state else {
            return
        }

        let wallet = Wallet(token: token, account: account)
        walletManager.save(wallets: [wallet])

        stat(page: .addToken, event: .addToken(token: token))
        finishSubject.send()
    }
}

extension AddTokenViewModel {
    enum State {
        case idle
        case loading
        case alreadyExists(token: Token)
        case fetched(token: Token)
        case failed(error: Error)
    }

    struct ViewItem {
        let name: String
        let code: String
        let decimals: String

        var fields: [(String, String)] {
            [
                ("add_token.coin_name".localized, name),
                ("add_token.symbol".localized, code),
                ("add_token.decimals".localized, decimals),
            ]
        }
    }

    struct CurrentBlockchainItem {
        let blockchain: Blockchain
        let placeholder: String

        init(item: AddTokenModule.Item) {
            blockchain = item.blockchain
            placeholder = item.service.placeholder
        }
    }
}
