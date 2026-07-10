import EvmKit
import Foundation

public class AccountFactory {
    private let accountManager: AccountManager

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }
}

public extension AccountFactory {
    var generatedAccountName: String {
        let index = Int.random(in: 1 ... 100)
        return NSLocalizedString("wallet_name.\(index)", bundle: .module, comment: "")
    }

    var nextAccountName: String {
        let nonWatchAccounts = accountManager.accounts.filter { !$0.watchAccount }
        return "Wallet \(nonWatchAccounts.count + 1)"
    }

    var nextWatchAccountName: String {
        let watchAccounts = accountManager.accounts.filter(\.watchAccount)
        return "Watch Wallet \(watchAccounts.count + 1)"
    }

    func account(type: AccountType, origin: AccountOrigin, backedUp: Bool, fileBackedUp: Bool, name: String) -> Account {
        Account(
            id: UUID().uuidString,
            level: accountManager.currentLevel,
            name: name,
            type: type,
            origin: origin,
            backedUp: backedUp,
            fileBackedUp: fileBackedUp
        )
    }

    func watchAccount(type: AccountType, name: String) -> Account {
        Account(
            id: UUID().uuidString,
            level: accountManager.currentLevel,
            name: name,
            type: type,
            origin: .restored,
            backedUp: true,
            fileBackedUp: false
        )
    }

}
