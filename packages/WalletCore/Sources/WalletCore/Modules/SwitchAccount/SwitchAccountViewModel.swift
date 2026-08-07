import Combine
import Dispatch

class SwitchAccountViewModel: ObservableObject {
    private let accountManager = Core.shared.accountManager
    private let childWalletBridge = ChildWalletBridge.shared
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var regularViewItems = [ViewItem]()
    @Published private(set) var watchViewItems = [ViewItem]()

    init() {
        accountManager.activeAccountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        accountManager.accountsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        childWalletBridge.activeChildWalletChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        sync()
    }

    private func sync() {
        let activeAccount = accountManager.activeAccount
        let items = accountManager.accounts.map { account in
            (account: account, displayName: childWalletBridge.displayName(account: account))
        }
        let sortedItems = items.sorted {
            $0.displayName.lowercased() < $1.displayName.lowercased()
        }

        regularViewItems = sortedItems
            .filter { !$0.account.watchAccount }
            .map { Self.viewItem(account: $0.account, activeAccount: activeAccount, displayName: $0.displayName) }
        watchViewItems = sortedItems
            .filter { $0.account.watchAccount }
            .map { Self.viewItem(account: $0.account, activeAccount: activeAccount, displayName: $0.displayName) }
    }

    private static func viewItem(account: Account, activeAccount: Account?, displayName: String) -> ViewItem {
        ViewItem(
            accountId: account.id,
            title: displayName,
            subtitle: account.type.detailedDescription,
            selected: account == activeAccount
        )
    }
}

extension SwitchAccountViewModel {
    func onSelect(accountId: String) {
        accountManager.set(activeAccountId: accountId)

        stat(page: .switchWallet, event: .select(entity: .wallet))
    }
}

extension SwitchAccountViewModel {
    struct ViewItem {
        let accountId: String
        let title: String
        let subtitle: String
        let selected: Bool
    }
}
