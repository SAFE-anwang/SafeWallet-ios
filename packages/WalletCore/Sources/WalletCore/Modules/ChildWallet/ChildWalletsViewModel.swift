import Combine
import Foundation

@MainActor
final class ChildWalletsViewModel: ObservableObject {
    private let bridge = ChildWalletBridge.shared
    private let walletManager = Core.shared.walletManager
    private let accountManager = Core.shared.accountManager

    let account: Account

    @Published private(set) var items = [Item]()
    @Published private(set) var activeChildWalletId: String?
    @Published var renameNameText = ""
    @Published var errorText: String?
    private var pendingChildWalletId: String?

    init(account: Account) {
        self.account = account
        sync()
    }

    private func sync() {
        activeChildWalletId = bridge.activeChildWalletId(account: account)

        do {
            let childWallets = try bridge.childWallets(parentAccountId: account.id)
                .sorted { $0.derivationIndex < $1.derivationIndex }

            items = [.root(isActive: activeChildWalletId == nil)] + childWallets.map {
                .child(wallet: $0, isActive: $0.id == activeChildWalletId)
            }
        } catch {
            errorText = error.smartDescription
            items = [.root(isActive: true)]
        }
    }

    private func refreshActiveWallets(activateAccount: Bool = true) {
        guard accountManager.activeAccount?.id == account.id else {
            if activateAccount {
                accountManager.set(activeAccountId: account.id)
                walletManager.preloadWallets()
            }

            return
        }

        walletManager.preloadWallets()
    }

    private func activateAndRefreshWallets() {
        if accountManager.activeAccount?.id != account.id {
            accountManager.set(activeAccountId: account.id)
        }

        walletManager.preloadWallets()
    }
}

extension ChildWalletsViewModel {
    var canCreateChildWallet: Bool {
        guard case .mnemonic = account.type else {
            return false
        }

        return account.type.mnemonicSeed != nil
    }

    var createDisabled: Bool {
        nextDerivationIndex == nil || !canCreateChildWallet
    }

    var createRequirementText: String? {
        guard canCreateChildWallet else {
            return nil
        }

        if nextDerivationIndex == nil {
            return "当前钱包已达到 500 个子钱包上限。"
        }

        return "新增会按 Index 升序创建下一个子钱包。"
    }

    func createNextChildWallet() {
        guard canCreateChildWallet else {
            errorText = ChildWalletError.unsupportedAccountType.localizedDescription
            return
        }

        guard nextDerivationIndex != nil else {
            errorText = "最多只能创建 500 个子钱包。"
            return
        }

        do {
            let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id)

            try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)
            sync()
            activateAndRefreshWallets()
        } catch {
            errorText = error.smartDescription
        }
    }

    func prepareRename(item: Item) -> Bool {
        guard let childWallet = item.childWallet else {
            return false
        }

        pendingChildWalletId = childWallet.id
        renameNameText = childWallet.name
        return true
    }

    func renamePendingChildWallet() {
        guard let pendingChildWalletId else {
            return
        }

        do {
            _ = try bridge.renameChildWallet(parentAccountId: account.id, childWalletId: pendingChildWalletId, name: renameNameText)
            self.pendingChildWalletId = nil
            sync()
        } catch {
            errorText = error.smartDescription
        }
    }

    func prepareHide(item: Item) -> Bool {
        guard let childWallet = item.childWallet else {
            return false
        }

        pendingChildWalletId = childWallet.id
        return true
    }

    func hidePendingChildWallet() {
        guard let pendingChildWalletId else {
            return
        }

        do {
            try bridge.hideChildWallet(parentAccountId: account.id, childWalletId: pendingChildWalletId)
            self.pendingChildWalletId = nil
            sync()
            activateAndRefreshWallets()
        } catch {
            errorText = error.smartDescription
        }
    }

    func select(item: Item) {
        do {
            try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: item.childWalletId)
            sync()
            activateAndRefreshWallets()
        } catch {
            errorText = error.smartDescription
        }
    }
}

private extension ChildWalletsViewModel {
    var nextDerivationIndex: Int? {
        try? bridge.nextDerivationIndex(parentAccountId: account.id)
    }
}

extension ChildWalletsViewModel {
    enum Item: Identifiable, Hashable {
        case root(isActive: Bool)
        case child(wallet: ChildWallet, isActive: Bool)

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.isActive == rhs.isActive
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(isActive)
        }

        var id: String {
            switch self {
            case .root:
                return "root"
            case let .child(wallet, _):
                return wallet.id
            }
        }

        var childWalletId: String? {
            switch self {
            case .root:
                return nil
            case let .child(wallet, _):
                return wallet.id
            }
        }

        var childWallet: ChildWallet? {
            switch self {
            case .root:
                return nil
            case let .child(wallet, _):
                return wallet
            }
        }

        var derivationIndex: Int? {
            switch self {
            case .root:
                return nil
            case let .child(wallet, _):
                return wallet.derivationIndex
            }
        }

        var title: String {
            switch self {
            case .root:
                return "主钱包"
            case let .child(wallet, _):
                return wallet.name
            }
        }

        var subtitle: String {
            switch self {
            case .root:
                return "默认派生地址"
            case let .child(wallet, _):
                return "Index \(wallet.derivationIndex)"
            }
        }

        var isActive: Bool {
            switch self {
            case let .root(isActive), let .child(_, isActive):
                return isActive
            }
        }
    }

}
