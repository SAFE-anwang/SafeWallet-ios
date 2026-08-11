import Combine
import Dispatch

class ManageAccountsViewModel: ObservableObject {
    private let accountManager = Core.shared.accountManager
    private let cloudBackupManager = Core.shared.cloudBackupManager
    private let childWalletBridge = ChildWalletBridge.shared
    private var cancellables = Set<AnyCancellable>()

    @Published var filter: String = "" {
        didSet { sync() }
    }

    @Published private(set) var sections = [Section]()

    init() {
        accountManager.activeAccountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        accountManager.accountsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        cloudBackupManager.$oneWalletItems
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
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let mapped = accountManager.accounts
            .map { account in
                let cloudBackedUp = cloudBackupManager.backedUp(uniqueId: account.type.uniqueId())
                return Item(
                    account: account,
                    displayName: childWalletBridge.displayName(account: account),
                    cloudBackedUp: cloudBackedUp,
                    isActive: account == activeAccount
                )
            }
            .filter { trimmed.isEmpty || $0.displayName.lowercased().contains(trimmed) }

        let regular = mapped.filter { !$0.account.watchAccount }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        let watch = mapped.filter(\.account.watchAccount)
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }

        var sections = [Section]()
        if !regular.isEmpty {
            sections.append(Section(kind: .wallets, items: regular))
        }
        if !watch.isEmpty {
            sections.append(Section(kind: .watchWallets, items: watch))
        }
        self.sections = sections
    }
}

extension ManageAccountsViewModel {
    var hasAccounts: Bool {
        !accountManager.accounts.isEmpty
    }

    func set(activeAccountId: String) {
        accountManager.set(activeAccountId: activeAccountId)
    }
}

extension ManageAccountsViewModel {
    struct Item: Hashable {
        let account: Account
        let displayName: String
        let cloudBackedUp: Bool
        let isActive: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(account)
            hasher.combine(displayName)
            hasher.combine(isActive)
        }
    }

    struct Section: Identifiable, Hashable {
        let kind: Kind
        let items: [Item]

        var id: Kind { kind }

        var title: String {
            switch kind {
            case .wallets: return "switch_account.wallets".localized
            case .watchWallets: return "switch_account.watch_wallets".localized
            }
        }
    }

    enum Kind: Hashable {
        case wallets
        case watchWallets
    }
}
